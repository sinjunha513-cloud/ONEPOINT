import {FieldValue, FieldPath, getFirestore, Timestamp, Transaction, DocumentData} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {documentId} from "./domain";
import {supportedSports} from "./models";
import {assertNotBlocked} from "./platform_access";

const options = {region: "asia-northeast3", maxInstances: 2, timeoutSeconds: 120};
const db = () => getFirestore();
const stamp = () => FieldValue.serverTimestamp();
const day = 86400000;
const activeStates = ["pending", "accepted", "confirmed"];
const millis = (v: unknown) => v instanceof Timestamp ? v.toMillis() : 0;
function input(r: CallableRequest, keys: string[]) {
  if (!r.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!r.data || typeof r.data !== "object" || Array.isArray(r.data) || Object.keys(r.data).some(k => !keys.includes(k))) throw new HttpsError("invalid-argument", "요청 항목을 확인해 주세요.");
  return r.data as Record<string, unknown>;
}
function reason(v: unknown) {
  if (typeof v !== "string" || !v.trim() || v.trim().length > 500) throw new HttpsError("invalid-argument", "사유를 1~500자로 입력해 주세요.");
  return v.trim();
}
function sameRevision(value: unknown, current: unknown) {
  if (!Number.isSafeInteger(value) || value !== Number(current ?? 0)) throw new HttpsError("failed-precondition", "요청 내용이 변경되었습니다. 최신 내용을 확인한 뒤 다시 처리해 주세요.");
}
async function member(tx: Transaction, uid: string) {
  const data = (await tx.get(db().collection("users").doc(uid))).data();
  if (!data || data.profileCompleted !== true || (data.accountStatus ?? "active") !== "active") throw new HttpsError("permission-denied", "활성 가입 완료 계정이 필요합니다.");
  return data;
}
async function coach(tx: Transaction, uid: string) {
  const account = await member(tx, uid);
  const profile = (await tx.get(db().collection("instructors").doc(uid))).data();
  if (account.role !== "coach" || profile?.status !== "approved" || profile.uid !== uid) throw new HttpsError("permission-denied", "담당 승인 코치가 필요합니다.");
  return profile;
}
function ordinary(data: DocumentData) {
  if (data.paymentRequired === true || Object.hasOwn(data, "price") || data.paymentId) throw new HttpsError("failed-precondition", "유료 레슨은 별도 절차를 이용해 주세요.");
}
function participant(data: DocumentData | undefined, uid: string): asserts data is DocumentData {
  if (!data || ![data.studentUid, data.instructorUid].includes(uid)) throw new HttpsError("permission-denied", "레슨 참여자만 요청할 수 있습니다.");
}
export function requestDeadline(data: DocumentData) {
  const deadline = millis(data.expiresAt) || (millis(data.createdAt) ? millis(data.createdAt) + day : 0);
  const start = millis(data.scheduledStartAt);
  return deadline && start ? Math.min(deadline, start) : deadline || start;
}
function live(data: DocumentData) {
  const paid = data.paymentRequired === true || Object.hasOwn(data, "price") || data.paymentId;
  return activeStates.includes(data.status) && !(data.status === "pending" && !paid && requestDeadline(data) && requestDeadline(data) <= Date.now());
}
function overlaps(a: number, b: number, c: number, d: number) { return a < d && c < b; }

// A shared per-member document serializes reservations across different coaches,
// slots and account roles, including queries which initially return no lessons.
async function calendars(tx: Transaction, uids: string[]) {
  const refs = [...new Set(uids)].sort().map(uid => db().collection("lesson_calendar_locks").doc(uid));
  await tx.getAll(...refs);
  const lessons = new Map<string, DocumentData>();
  for (const uid of [...new Set(uids)]) {
    const snapshot = await tx.get(db().collection("lesson_requests").where("participantIds", "array-contains", uid));
    for (const doc of snapshot.docs) lessons.set(doc.id, doc.data());
  }
  return {lessons, write() { for (const ref of refs) tx.set(ref, {revision: FieldValue.increment(1), updatedAt: stamp()}, {merge: true}); }};
}
function checkRange(calendar: Awaited<ReturnType<typeof calendars>>, start: number, end: number, except?: string) {
  for (const [id, other] of calendar.lessons) {
    if (id === except || !live(other)) continue;
    if (overlaps(start, end, millis(other.scheduledStartAt), millis(other.scheduledEndAt))) throw new HttpsError("already-exists", "수강생 또는 코치의 다른 레슨과 시간이 겹칩니다.");
    const p = other.scheduleProposal;
    if (p?.status === "pending" && millis(p.expiresAt) > Date.now() && overlaps(start, end, millis(p.startAt), millis(p.endAt))) throw new HttpsError("already-exists", "승인 대기 중인 변경 일정과 시간이 겹칩니다.");
  }
}
async function resources(tx: Transaction, id: string, data: DocumentData) {
  const slotIds = [...new Set([data.slotId, data.scheduleProposal?.slotId].filter(v => typeof v === "string"))] as string[];
  const slots: {ref: FirebaseFirestore.DocumentReference; data: DocumentData | undefined}[] = [];
  for (const slot of slotIds) {
    const ref = db().collection("instructors").doc(data.instructorUid).collection("availability").doc(slot);
    slots.push({ref, data: (await tx.get(ref)).data()});
  }
  const keys = [...new Set([data.activeRequestKey, `${data.instructorUid}_${data.studentUid}`].filter(v => typeof v === "string"))] as string[];
  const pairs: {ref: FirebaseFirestore.DocumentReference; data: DocumentData | undefined}[] = [];
  for (const key of keys) {
    const ref = db().collection("active_lesson_requests").doc(key);
    pairs.push({ref, data: (await tx.get(ref)).data()});
  }
  const release = (onlySlot?: string) => {
    for (const slot of slots) if ((!onlySlot || slot.ref.id === onlySlot) && slot.data?.lessonId === id) {
      tx.update(slot.ref, {status: "available", lessonId: FieldValue.delete(), studentUid: FieldValue.delete(), holdExpiresAt: FieldValue.delete(), updatedAt: stamp()});
    }
    if (!onlySlot) for (const pair of pairs) if (pair.data?.requestId === id) tx.delete(pair.ref);
  };
  return {slots, release};
}
function audit(tx: Transaction, id: string, action: string, uid: string, extra: DocumentData = {}) {
  tx.create(db().collection("lesson_requests").doc(id).collection("workflow_history").doc(), {action, actorUid: uid, createdAt: stamp(), ...extra});
}
export async function expireLesson(id: string) {
  await db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), data = (await tx.get(ref)).data();
    if (!data || !activeStates.includes(data.status) || data.paymentRequired === true || Object.hasOwn(data, "price") || data.paymentId) return;
    const due = data.status === "pending" && requestDeadline(data) > 0 && requestDeadline(data) <= Date.now();
    const proposalDue = data.scheduleProposal?.status === "pending" && millis(data.scheduleProposal.expiresAt) <= Date.now();
    if (!due && !proposalDue) return;
    const calendar = await calendars(tx, [data.studentUid, data.instructorUid]);
    const held = await resources(tx, id, data);
    if (due) {
      held.release();
      tx.update(ref, {status: "expired", expiredAt: stamp(), updatedAt: stamp(), ...(data.scheduleProposal ? {scheduleProposal: {...data.scheduleProposal, status: "expired"}} : {})});
      audit(tx, id, "request_expired", "system");
    } else {
      held.release(data.scheduleProposal.slotId);
      tx.update(ref, {scheduleProposal: {...data.scheduleProposal, status: "expired", respondedAt: stamp()}, updatedAt: stamp()});
      audit(tx, id, "schedule_expired", "system");
    }
    calendar.write();
  });
}
export const expireLessonRequests = onSchedule({...options, schedule: "every 5 minutes", timeZone: "Asia/Seoul"}, async () => {
  for (const status of ["pending", "accepted"]) {
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    while (true) {
      let query = db().collection("lesson_requests").where("status", "==", status).orderBy(FieldPath.documentId()).limit(200);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const doc of page.docs) await expireLesson(doc.id);
      if (page.size < 200) break;
      cursor = page.docs.at(-1);
    }
  }
});

async function createRequest(r: CallableRequest, withSlot: boolean) {
  const data = input(r, withSlot ? ["instructorId", "slotId"] : ["instructorId"]), uid = r.auth!.uid;
  const coachUid = documentId(data.instructorId, "instructorId");
  if (uid === coachUid) throw new HttpsError("invalid-argument", "본인에게 신청할 수 없습니다.");
  const slotRef = withSlot ? db().collection("instructors").doc(coachUid).collection("availability").doc(documentId(data.slotId, "slotId")) : null;
  if (slotRef) { const current = (await slotRef.get()).data(); if (typeof current?.lessonId === "string") await expireLesson(current.lessonId); }
  const ref = db().collection("lesson_requests").doc();
  await db().runTransaction(async tx => {
    const student = await member(tx, uid), profile = await coach(tx, coachUid);
    await assertNotBlocked(tx, uid, coachUid);
    if (!["student", "coach", "admin"].includes(student.role) || !(supportedSports as readonly string[]).includes(profile.sport)) throw new HttpsError("permission-denied", "신청 가능한 회원과 코치가 필요합니다.");
    const slot = slotRef ? (await tx.get(slotRef)).data() : null;
    const calendar = await calendars(tx, [uid, coachUid]);
    const legacyPair = slotRef ? null : (await tx.get(db().collection("active_lesson_requests").doc(`${coachUid}_${uid}`))).data();
    if (slotRef) {
      if (!slot || slot.status !== "available" || millis(slot.startAt) <= Date.now() || millis(slot.endAt) <= millis(slot.startAt)) throw new HttpsError("failed-precondition", "예약 가능한 시간이 아닙니다.");
      checkRange(calendar, millis(slot.startAt), millis(slot.endAt));
    } else if ([...calendar.lessons.entries()].some(([id, other]) => live(other) && other.studentUid === uid && other.instructorUid === coachUid && !other.slotId && (other.workflowVersion === 2 || legacyPair?.requestId === id))) {
      throw new HttpsError("already-exists", "날짜 협의 중인 신청이 있습니다. 날짜를 먼저 정해 주세요.");
    }
    const expires = Math.min(Date.now() + day, slot ? millis(slot.startAt) : Infinity);
    const ids = [uid, coachUid].sort();
    tx.create(ref, {workflowVersion: 2, activeRequestKey: ref.id, instructorId: coachUid, instructorUid: coachUid, instructorName: profile.name,
      studentUid: uid, studentName: student.name, participantIds: ids, sport: profile.sport,
      ...Object.fromEntries(["signatureMove", "signatureBadgeId", "signatureBadgeColorIndex"].filter(k => profile[k] !== undefined).map(k => [k, profile[k]])),
      status: "pending", paymentRequired: false, isInstructorInitiated: false, createdAt: stamp(), expiresAt: Timestamp.fromMillis(expires),
      ...(slot ? {slotId: slotRef!.id, scheduledStartAt: slot.startAt, scheduledEndAt: slot.endAt} : {})});
    tx.create(db().collection("active_lesson_requests").doc(ref.id), {requestId: ref.id, participantIds: ids});
    if (slotRef) tx.update(slotRef, {status: "booked", lessonId: ref.id, updatedAt: stamp()});
    calendar.write();
  });
  return {lessonId: ref.id};
}
export const requestLesson = onCall(options, r => createRequest(r, false));
export const requestLessonWithSlot = onCall(options, r => createRequest(r, true));

async function changeStatus(r: CallableRequest, status: "accepted" | "rejected" | "cancelled") {
  const data = input(r, ["lessonId", "reason"]), id = documentId(data.lessonId, "lessonId"), uid = r.auth!.uid;
  await expireLesson(id);
  return db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    participant(lesson, uid); await member(tx, uid); ordinary(lesson);
    if (status !== "cancelled" && lesson.instructorUid !== uid) throw new HttpsError("permission-denied", "담당 코치만 수락·거절할 수 있습니다.");
    if (status !== "cancelled") await coach(tx, uid);
    if (lesson.status === status) return {lessonId: id, status};
    if (status === "cancelled") {
      if (!["pending", "accepted"].includes(lesson.status)) throw new HttpsError("failed-precondition", "현재 취소할 수 없는 레슨입니다.");
      if (lesson.status === "accepted" && millis(lesson.scheduledStartAt) && millis(lesson.scheduledStartAt) <= Date.now()) throw new HttpsError("failed-precondition", "수업 시작 후에는 완료 확인 또는 이의 제기를 이용해 주세요.");
    } else if (lesson.status !== "pending" || (requestDeadline(lesson) && requestDeadline(lesson) <= Date.now())) throw new HttpsError("failed-precondition", "응답 기한 내 대기 중인 신청만 처리할 수 있습니다.");
    const note = status === "cancelled" && lesson.status === "accepted" ? reason(data.reason) : typeof data.reason === "string" ? data.reason.trim().slice(0, 500) : "";
    const calendar = await calendars(tx, [lesson.studentUid, lesson.instructorUid]);
    const held = await resources(tx, id, lesson);
    const roomId = [lesson.studentUid, lesson.instructorUid].sort().join("_");
    const roomRef = db().collection("chat_rooms").doc(roomId), room = status === "accepted" ? await tx.get(roomRef) : null;
    if (status === "accepted") {
      await member(tx, lesson.studentUid);
      if (millis(lesson.scheduledStartAt)) checkRange(calendar, millis(lesson.scheduledStartAt), millis(lesson.scheduledEndAt), id);
      if (lesson.slotId && !held.slots.some(s => s.ref.id === lesson.slotId && s.data?.lessonId === id && s.data?.status === "booked")) throw new HttpsError("failed-precondition", "예약 시간 연결을 확인해 주세요.");
      if (!room?.exists) tx.create(roomRef, {participantIds: [lesson.studentUid, lesson.instructorUid].sort(), studentUid: lesson.studentUid,
        studentName: lesson.studentName, coachUid: lesson.instructorUid, coachName: lesson.instructorName});
    } else held.release();
    tx.update(ref, {status, updatedAt: stamp(), ...(status === "cancelled" ? {cancelledAt: stamp(), cancelledBy: uid, cancellationReason: note} : {})});
    audit(tx, id, status, uid, {reason: note}); calendar.write();
    return {lessonId: id, status};
  });
}
export const acceptLesson = onCall(options, r => changeStatus(r, "accepted"));
export const rejectLesson = onCall(options, r => changeStatus(r, "rejected"));
export const cancelLesson = onCall(options, r => changeStatus(r, "cancelled"));

export const rescheduleLesson = onCall(options, async r => {
  const data = input(r, ["lessonId", "slotId"]), uid = r.auth!.uid, id = documentId(data.lessonId, "lessonId"), slotId = documentId(data.slotId, "slotId");
  await expireLesson(id);
  return db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    participant(lesson, uid); await member(tx, uid); ordinary(lesson); await coach(tx, lesson.instructorUid);
    if (!["pending", "accepted"].includes(lesson.status) || !live(lesson) || lesson.completionReview?.status === "pending") throw new HttpsError("failed-precondition", "현재 일정을 변경할 수 없습니다.");
    if (lesson.scheduleProposal?.status === "pending") throw new HttpsError("already-exists", "기존 변경 요청을 먼저 처리하거나 철회해 주세요.");
    if (lesson.slotId === slotId) throw new HttpsError("invalid-argument", "현재와 다른 시간을 선택해 주세요.");
    const nextRef = db().collection("instructors").doc(lesson.instructorUid).collection("availability").doc(slotId), next = (await tx.get(nextRef)).data();
    const calendar = await calendars(tx, [lesson.studentUid, lesson.instructorUid]);
    if (!next || next.status !== "available" || millis(next.startAt) <= Date.now() || millis(next.endAt) <= millis(next.startAt)) throw new HttpsError("failed-precondition", "예약 가능한 시간이 아닙니다.");
    checkRange(calendar, millis(next.startAt), millis(next.endAt), id);
    const expiresAt = Timestamp.fromMillis(Math.min(Date.now() + day, millis(next.startAt), lesson.status === "pending" ? requestDeadline(lesson) || Infinity : Infinity));
    const revision = Number(lesson.scheduleProposal?.revision ?? 0) + 1;
    tx.update(nextRef, {status: "held", lessonId: id, holdExpiresAt: expiresAt, updatedAt: stamp()});
    tx.update(ref, {scheduleProposal: {status: "pending", revision, requestedBy: uid, slotId, startAt: next.startAt, endAt: next.endAt, expiresAt, requestedAt: stamp()}, updatedAt: stamp()});
    audit(tx, id, "schedule_requested", uid, {slotId, revision}); calendar.write();
    return {lessonId: id, status: "pending", revision};
  });
});
export const respondScheduleChange = onCall(options, async r => {
  const data = input(r, ["lessonId", "decision", "revision"]), uid = r.auth!.uid, id = documentId(data.lessonId, "lessonId");
  if (!["approve", "reject", "withdraw"].includes(data.decision as string)) throw new HttpsError("invalid-argument", "응답을 확인해 주세요.");
  await expireLesson(id);
  return db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    participant(lesson, uid); const actor = await member(tx, uid); ordinary(lesson);
    const proposal = lesson.scheduleProposal;
    if (!proposal || proposal.status !== "pending" || millis(proposal.expiresAt) <= Date.now() || !live(lesson) || !["pending", "accepted"].includes(lesson.status)) throw new HttpsError("failed-precondition", "대기 중인 변경 요청이 없습니다.");
    if ((data.decision === "withdraw") !== (proposal.requestedBy === uid)) throw new HttpsError("permission-denied", "변경 요청의 상대방만 승인·거절할 수 있습니다.");
    sameRevision(data.revision, proposal.revision);
    const calendar = await calendars(tx, [lesson.studentUid, lesson.instructorUid]), held = await resources(tx, id, lesson);
    const next = held.slots.find(s => s.ref.id === proposal.slotId);
    const result = data.decision === "approve" ? "approved" : data.decision === "reject" ? "rejected" : "withdrawn";
    if (data.decision === "approve") {
      await coach(tx, lesson.instructorUid); await member(tx, lesson.studentUid);
      if (!next || next.data?.status !== "held" || next.data?.lessonId !== id || millis(proposal.startAt) <= Date.now()) throw new HttpsError("failed-precondition", "임시 확보한 시간이 만료되었습니다.");
      checkRange(calendar, millis(proposal.startAt), millis(proposal.endAt), id);
      if (lesson.slotId) held.release(lesson.slotId);
      tx.update(next.ref, {status: "booked", holdExpiresAt: FieldValue.delete(), updatedAt: stamp()});
      tx.update(ref, {slotId: proposal.slotId, scheduledStartAt: proposal.startAt, scheduledEndAt: proposal.endAt,
        scheduleRevision: FieldValue.increment(1), completionReview: FieldValue.delete(),
        ...(lesson.status === "pending" ? {expiresAt: Timestamp.fromMillis(Math.min(requestDeadline(lesson) || Date.now() + day, millis(proposal.startAt)))} : {})});
      tx.create(ref.collection("schedule_changes").doc(), {changedBy: uid, changedByName: actor.name ?? "회원",
        changedAt: stamp(), previousStartAt: lesson.scheduledStartAt ?? null, previousEndAt: lesson.scheduledEndAt ?? null, newStartAt: proposal.startAt, newEndAt: proposal.endAt, slotId: proposal.slotId});
    } else held.release(proposal.slotId);
    tx.update(ref, {scheduleProposal: {...proposal, status: result, respondedBy: uid, respondedAt: stamp()}, updatedAt: stamp()});
    audit(tx, id, `schedule_${result}`, uid); calendar.write();
    return {lessonId: id, status: result};
  });
});

function ended(lesson: DocumentData) {
  if (!millis(lesson.scheduledStartAt) || millis(lesson.scheduledEndAt) <= millis(lesson.scheduledStartAt) || millis(lesson.scheduledEndAt) > Date.now()) throw new HttpsError("failed-precondition", "확정된 수업 종료 시간이 지난 후에 완료를 확인할 수 있습니다.");
  if (lesson.scheduleProposal?.status === "pending") throw new HttpsError("failed-precondition", "일정 변경 요청을 먼저 처리해 주세요.");
}
// Test completion never invents payment/settlement state. Only an operator
// feature flag can permit an unpaid quote through the ordinary review flow.
async function completionMode(tx: Transaction, id: string, lesson: DocumentData) {
  const config=(await tx.get(db().doc('app_config/features'))).data();
  if(config?.lessonTestModeEnabled!==true){ordinary(lesson);return false;}
  if(lesson.paymentId || (lesson.paymentStatus!=null && !['pending','unpaid'].includes(lesson.paymentStatus))) {
    throw new HttpsError('failed-precondition','결제 기록이 연결된 레슨은 기존 결제 절차를 이용해 주세요.');
  }
  const payments=await tx.get(db().collection('payments').where('lessonId','==',id).limit(1));
  if(!payments.empty)throw new HttpsError('failed-precondition','결제 기록이 연결된 레슨은 기존 결제 절차를 이용해 주세요.');
  return true;
}
export const completeLesson = onCall(options, async r => {
  const data = input(r, ["lessonId", "reviewScore", "feedback", "signatureMove"]), uid = r.auth!.uid, id = documentId(data.lessonId, "lessonId");
  if (typeof data.reviewScore !== "number" || !Number.isFinite(data.reviewScore) || data.reviewScore < 1 || data.reviewScore > 5 || typeof data.feedback !== "string" || data.feedback.length > 1000) throw new HttpsError("invalid-argument", "평가와 피드백을 확인해 주세요.");
  return db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    if (!lesson || lesson.instructorUid !== uid) throw new HttpsError("permission-denied", "담당 코치만 완료 확인을 요청할 수 있습니다.");
    const profile = await coach(tx, uid); await member(tx, lesson.studentUid);
    if (lesson.status === "completed") return {lessonId: id, status: "completed"};
    const testWithoutPayment=await completionMode(tx,id,lesson);
    if (lesson.status !== "accepted") throw new HttpsError("failed-precondition", "수락한 레슨만 완료 확인을 요청할 수 있습니다.");
    ended(lesson);
    if (lesson.completionReview?.status === "disputed") throw new HttpsError("failed-precondition", "이의 제기 검토 또는 합의된 일정 변경 후 다시 요청해 주세요.");
    if (lesson.completionReview?.status === "pending") return {lessonId: id, status: "pending"};
    const badgeId = profile.signatureBadgeId ?? lesson.signatureBadgeId;
    const badge = badgeId ? (await tx.get(db().collection("signature_badges").doc(documentId(badgeId, "badgeId")))).data() : null;
    if (badgeId && !badge) throw new HttpsError("failed-precondition", "시그니처 뱃지를 다시 등록해 주세요.");
    const signature = badge?.name ?? profile.signatureMove ?? lesson.signatureMove;
    if (typeof signature !== "string" || !signature.trim() || signature.length > 40 || (data.signatureMove && data.signatureMove !== signature)) throw new HttpsError("failed-precondition", "시그니처 기술을 확인해 주세요.");
    const revision = Number(lesson.completionRevision ?? lesson.completionReview?.revision ?? 0) + 1;
    const attendanceBadge = {instructorUid: uid, instructorName: lesson.instructorName ?? profile.name ?? "코치", sport: lesson.sport ?? profile.sport ?? "",
      signatureMove: signature, verifiedBy: uid, ...(badgeId ? {signatureBadgeId: badgeId} : {}),
      ...(typeof (badge?.colorIndex ?? profile.signatureBadgeColorIndex) === "number" ? {signatureBadgeColorIndex: badge?.colorIndex ?? profile.signatureBadgeColorIndex} : {})};
    tx.update(ref, {completionRevision: revision, completionReview: {status: "pending", revision, requestedBy: uid, requestedAt: stamp(), reviewScore: data.reviewScore, feedback: data.feedback, attendanceBadge, ...(testWithoutPayment?{testWithoutPayment:true}:{})}, updatedAt: stamp()});
    audit(tx, id, "completion_requested", uid, {revision,...(testWithoutPayment?{testWithoutPayment:true}:{})});
    return {lessonId: id, status: "pending"};
  });
});
async function finalize(tx: Transaction, id: string, lesson: DocumentData, actorUid: string, adminReason?: string) {
  const review = lesson.completionReview;
  if (review?.requestedBy !== lesson.instructorUid || !review.attendanceBadge || typeof review.reviewScore !== "number") throw new HttpsError("failed-precondition", "코치의 완료 확인 요청이 필요합니다.");
  const student = await member(tx, lesson.studentUid), held = await resources(tx, id, lesson), calendar = await calendars(tx, [lesson.studentUid, lesson.instructorUid]);
  held.release(); calendar.write();
  tx.update(db().collection("lesson_requests").doc(id), {status: "completed", completedAt: stamp(), updatedAt: stamp(), reviewScore: review.reviewScore, reviewFeedback: review.feedback,
    attendanceBadge: {...review.attendanceBadge, awardedAt: stamp()}, completionReview: {...review, status: adminReason ? "resolved" : "confirmed", confirmedBy: actorUid, confirmedAt: stamp(), ...(adminReason ? {resolutionReason: adminReason} : {})}});
  tx.update(db().collection("users").doc(lesson.studentUid), {lastCompletedLessonId: id, lessonCount: FieldValue.increment(1), reviewScores: [...(student.reviewScores ?? []), review.reviewScore], ...(lesson.isInstructorInitiated ? {teacherMatchCount: FieldValue.increment(1)} : {})});
  audit(tx, id, "completion_confirmed", actorUid, {reason: adminReason ?? "수강생 참여 확인"});
}
export const respondLessonCompletion = onCall(options, async r => {
  const data = input(r, ["lessonId", "decision", "reason", "revision"]), uid = r.auth!.uid, id = documentId(data.lessonId, "lessonId");
  if (!["confirm", "dispute"].includes(data.decision as string)) throw new HttpsError("invalid-argument", "응답을 확인해 주세요.");
  return db().runTransaction(async tx => {
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    if (!lesson || lesson.studentUid !== uid) throw new HttpsError("permission-denied", "담당 수강생만 참여를 확인할 수 있습니다.");
    await member(tx, uid);
    if (lesson.status === "completed" && data.decision === "confirm") return {lessonId: id, status: "completed"};
    await completionMode(tx,id,lesson);
    if (lesson.status !== "accepted") throw new HttpsError("failed-precondition", "현재 참여 확인을 처리할 수 없습니다.");
    ended(lesson);
    sameRevision(data.revision, lesson.completionReview?.revision);
    if (data.decision === "confirm") {
      if (lesson.completionReview?.status !== "pending") throw new HttpsError("failed-precondition", "대기 중인 완료 확인 요청이 없습니다.");
      await finalize(tx, id, lesson, uid);
    } else {
      const note = reason(data.reason);
      if (lesson.completionReview?.status === "disputed") return {lessonId: id, status: "disputed"};
      const revision = Number(lesson.completionRevision ?? lesson.completionReview?.revision ?? 0) + 1;
      tx.update(ref, {completionRevision: revision, completionReview: {...(lesson.completionReview ?? {}), status: "disputed", revision, disputedBy: uid, disputedAt: stamp(), disputeReason: note}, updatedAt: stamp()});
      audit(tx, id, "completion_disputed", uid, {reason: note});
    }
    return {lessonId: id, status: data.decision === "confirm" ? "completed" : "disputed"};
  });
});
export const resolveLessonDispute = onCall(options, async r => {
  const data = input(r, ["lessonId", "decision", "reason", "revision"]), uid = r.auth!.uid, id = documentId(data.lessonId, "lessonId"), note = reason(data.reason);
  if (!["confirm", "reopen", "cancel"].includes(data.decision as string)) throw new HttpsError("invalid-argument", "처리 방법을 확인해 주세요.");
  return db().runTransaction(async tx => {
    if ((await member(tx, uid)).role !== "admin") throw new HttpsError("permission-denied", "관리자만 이의 제기를 처리할 수 있습니다.");
    const ref = db().collection("lesson_requests").doc(id), lesson = (await tx.get(ref)).data();
    if (!lesson || lesson.status !== "accepted" || lesson.completionReview?.status !== "disputed") throw new HttpsError("failed-precondition", "검토 중인 이의 제기가 없습니다.");
    await completionMode(tx,id,lesson); ended(lesson);
    sameRevision(data.revision, lesson.completionReview.revision);
    if (data.decision === "confirm") await finalize(tx, id, lesson, uid, note);
    else {
      const calendar = await calendars(tx, [lesson.studentUid, lesson.instructorUid]), held = await resources(tx, id, lesson);
      if (data.decision === "cancel") held.release();
      calendar.write();
      tx.update(ref, {status: data.decision === "cancel" ? "cancelled" : "accepted", completionReview: {...lesson.completionReview, status: data.decision === "cancel" ? "cancelled" : "reopened", resolvedBy: uid, resolvedAt: stamp(), resolutionReason: note}, updatedAt: stamp(), ...(data.decision === "cancel" ? {cancelledBy: uid, cancellationReason: note, cancelledAt: stamp()} : {})});
      audit(tx, id, `dispute_${data.decision}`, uid, {reason: note});
    }
    return {lessonId: id, status: data.decision};
  });
});
export async function releaseClosedLesson(id: string) {
  await db().runTransaction(async tx => {
    const lesson = (await tx.get(db().collection("lesson_requests").doc(id))).data();
    if (!lesson || !["cancelled", "rejected", "expired"].includes(lesson.status)) return;
    const held = await resources(tx, id, lesson); held.release();
  });
}
