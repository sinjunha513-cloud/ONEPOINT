import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {onDocumentUpdated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {documentId} from "./domain";
const options = {region: "asia-northeast3", maxInstances: 2};
const db = () => getFirestore();
function uidOf(r: CallableRequest) { if (!r.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다."); return r.auth.uid; }
async function coach(tx: FirebaseFirestore.Transaction, uid: string) {
  const user = (await tx.get(db().collection("users").doc(uid))).data();
  const profile = (await tx.get(db().collection("instructors").doc(uid))).data();
  if (!user || user.role !== "coach" || user.profileCompleted !== true || (user.accountStatus ?? "active") !== "active" || profile?.status !== "approved") throw new HttpsError("permission-denied", "활성 승인 코치가 필요합니다.");
}
async function save(r: CallableRequest, bulk: boolean) {
  const uid = uidOf(r); const input = r.data;
  const ranges = bulk ? input?.slots : [input];
  if (!Array.isArray(ranges) || ranges.length < 1 || ranges.length > 100) throw new HttpsError("invalid-argument", "시간을 확인해 주세요.");
  const slots = db().collection("instructors").doc(uid).collection("availability");
  const parsed = ranges.map((range: Record<string, unknown>) => {
    if (!range || !Number.isSafeInteger(range.startAtMillis) || !Number.isSafeInteger(range.endAtMillis) || (range.startAtMillis as number) <= Date.now() || (range.endAtMillis as number) <= (range.startAtMillis as number) || (range.endAtMillis as number) - (range.startAtMillis as number) > 24 * 3600000) throw new HttpsError("invalid-argument", "미래의 시작·종료 시간을 확인해 주세요.");
    return {ref: !bulk && input.slotId ? slots.doc(documentId(input.slotId, "slotId")) : slots.doc(), start: range.startAtMillis as number, end: range.endAtMillis as number};
  });
  await db().runTransaction(async tx => {
    await coach(tx, uid);
    const current = await tx.get(slots);
    for (const slot of parsed) {
      const old = current.docs.find(d => d.id === slot.ref.id)?.data();
      if (old && old.status !== "available") throw new HttpsError("failed-precondition", "예약된 시간은 수정할 수 없습니다.");
      if (current.docs.some(d => d.id !== slot.ref.id && d.data().startAt.toMillis() < slot.end && d.data().endAt.toMillis() > slot.start) || parsed.some(other => other !== slot && other.start < slot.end && other.end > slot.start)) throw new HttpsError("already-exists", "겹치는 시간이 있습니다.");
    }
    for (const slot of parsed) tx.set(slot.ref, {coachUid: uid, startAt: Timestamp.fromMillis(slot.start), endAt: Timestamp.fromMillis(slot.end), status: "available", updatedAt: FieldValue.serverTimestamp()});
  });
  return bulk ? {slotIds: parsed.map(s => s.ref.id)} : {slotId: parsed[0].ref.id};
}
export const saveAvailabilitySlot = onCall(options, r => save(r, false));
export const saveAvailabilitySlots = onCall(options, r => save(r, true));
export const deleteAvailabilitySlot = onCall(options, async r => {
  const uid = uidOf(r); const ref = db().collection("instructors").doc(uid).collection("availability").doc(documentId(r.data?.slotId, "slotId"));
  await db().runTransaction(async tx => { await coach(tx, uid); const slot = (await tx.get(ref)).data(); if (!slot || slot.status !== "available") throw new HttpsError("failed-precondition", "예약되지 않은 시간만 삭제할 수 있습니다."); tx.delete(ref); });
  return {deleted: true};
});
export const rescheduleLesson = onCall(options, async r => {
  const uid = uidOf(r); const lessonId = documentId(r.data?.lessonId, "lessonId"); const slotId = documentId(r.data?.slotId, "slotId");
  const ref = db().collection("lesson_requests").doc(lessonId);
  await db().runTransaction(async tx => {
    const lesson = (await tx.get(ref)).data();
    if (!lesson || ![lesson.instructorUid, lesson.studentUid].includes(uid) || !["pending", "accepted", "confirmed"].includes(lesson.status)) throw new HttpsError("permission-denied", "레슨 참여자만 일정을 변경할 수 있습니다.");
    const actor = (await tx.get(db().collection("users").doc(uid))).data();
    if (!actor || actor.profileCompleted !== true || (actor.accountStatus ?? "active") !== "active") throw new HttpsError("permission-denied", "활성 가입 완료 계정이 필요합니다.");
    await coach(tx, lesson.instructorUid);
    const slots = db().collection("instructors").doc(lesson.instructorUid).collection("availability");
    const nextRef = slots.doc(slotId); const next = (await tx.get(nextRef)).data();
    const oldRef = typeof lesson.slotId === "string" ? slots.doc(lesson.slotId) : null;
    const old = oldRef ? (await tx.get(oldRef)).data() : null;
    if (lesson.slotId === slotId) return;
    if (!next || next.status !== "available" || next.startAt.toMillis() <= Date.now()) throw new HttpsError("failed-precondition", "예약 가능한 시간이 아닙니다.");
    tx.update(nextRef, {status: "booked", lessonId, updatedAt: FieldValue.serverTimestamp()});
    if (oldRef && old?.lessonId === lessonId) tx.update(oldRef, {status: "available", lessonId: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
    tx.update(ref, {slotId, scheduledStartAt: next.startAt, scheduledEndAt: next.endAt, scheduleRevision: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
    tx.create(ref.collection("schedule_changes").doc(), {changedBy: uid, changedByName: actor.name, changedAt: FieldValue.serverTimestamp(), previousStartAt: lesson.scheduledStartAt ?? null, previousEndAt: lesson.scheduledEndAt ?? null, newStartAt: next.startAt, newEndAt: next.endAt, slotId});
  });
  return {lessonId, slotId};
});
export const projectPublicAvailability = onDocumentWritten({...options, document: "instructors/{uid}/availability/{slot}"}, async e => {
  await projectSlot(e.params.uid, e.params.slot);
});
export async function projectSlot(uid: string, slotId: string) {
  await db().runTransaction(async tx => {
    const slot = (await tx.get(db().collection("instructors").doc(uid).collection("availability").doc(slotId))).data();
    const ref = db().collection("instructors").doc(uid).collection("public_availability").doc(slotId);
    if (!slot) { tx.delete(ref); return; }
    tx.set(ref, {coachUid: uid, startAt: slot.startAt, endAt: slot.endAt, status: slot.status});
  });
}
export const releaseCancelledSlot = onDocumentUpdated({...options, document: "lesson_requests/{id}"}, async e => {
  if (!["rejected", "cancelled"].includes(e.data?.after.data().status)) return;
  await db().runTransaction(async tx => {
    const lesson = (await tx.get(e.data!.after.ref)).data();
    if (!lesson || !["rejected", "cancelled"].includes(lesson.status)) return;
    const pairRef = db().collection("active_lesson_requests").doc(`${lesson.instructorUid}_${lesson.studentUid}`);
    const pair = (await tx.get(pairRef)).data();
    const ref = typeof lesson.slotId === "string" ? db().collection("instructors").doc(lesson.instructorUid).collection("availability").doc(lesson.slotId) : null;
    const slot = ref ? (await tx.get(ref)).data() : null;
    if (pair?.requestId === e.params.id) tx.delete(pairRef);
    if (ref && slot?.lessonId === e.params.id) tx.update(ref, {status: "available", lessonId: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
  });
});
