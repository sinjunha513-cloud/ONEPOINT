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
  if (input?.coachUid !== undefined && input.coachUid !== uid) throw new HttpsError("permission-denied", "로그인 계정이 변경되었습니다. 다시 시도해 주세요.");
  const ranges = bulk ? input?.slots : [input];
  if (!Array.isArray(ranges) || ranges.length < 1 || ranges.length > 100) throw new HttpsError("invalid-argument", "시간을 확인해 주세요.");
  const slots = db().collection("instructors").doc(uid).collection("availability");
  const parsed = ranges.map((range: Record<string, unknown>) => {
    if (!range || !Number.isSafeInteger(range.startAtMillis) || !Number.isSafeInteger(range.endAtMillis) || (range.startAtMillis as number) <= Date.now() || (range.endAtMillis as number) <= (range.startAtMillis as number) || (range.endAtMillis as number) - (range.startAtMillis as number) > 24 * 3600000) throw new HttpsError("invalid-argument", "미래의 시작·종료 시간을 확인해 주세요.");
    return {ref: bulk ? slots.doc(`bulk_${range.startAtMillis}_${range.endAtMillis}`) : input.slotId ? slots.doc(documentId(input.slotId, "slotId")) : slots.doc(), start: range.startAtMillis as number, end: range.endAtMillis as number};
  });
  if (parsed.some(slot => parsed.some(other => other !== slot && other.start < slot.end && other.end > slot.start))) throw new HttpsError("already-exists", "겹치는 시간이 있습니다.");
  let ids: string[] = [];
  await db().runTransaction(async tx => {
    await coach(tx, uid);
    const current = await tx.get(slots);
    ids = [];
    const writes: typeof parsed = [];
    for (const slot of parsed) {
      // Retrying a chunk must not duplicate it or reopen a slot booked meanwhile.
      const exact = bulk ? current.docs.find(d => d.data().startAt.toMillis() === slot.start && d.data().endAt.toMillis() === slot.end) : undefined;
      if (exact && (exact.id === slot.ref.id || exact.data().status === "available")) { ids.push(exact.id); continue; }
      const old = current.docs.find(d => d.id === slot.ref.id)?.data();
      if (bulk && old) throw new HttpsError("failed-precondition", "이전에 등록한 시간이 수정되었습니다. 현재 일정을 확인해 주세요.");
      if (old && old.status !== "available") throw new HttpsError("failed-precondition", "예약된 시간은 수정할 수 없습니다.");
      if (current.docs.some(d => d.id !== slot.ref.id && d.data().startAt.toMillis() < slot.end && d.data().endAt.toMillis() > slot.start)) throw new HttpsError("already-exists", "겹치는 시간이 있습니다.");
      ids.push(slot.ref.id);
      writes.push(slot);
    }
    for (const slot of writes) tx.set(slot.ref, {coachUid: uid, startAt: Timestamp.fromMillis(slot.start), endAt: Timestamp.fromMillis(slot.end), status: "available", updatedAt: FieldValue.serverTimestamp()});
  });
  return bulk ? {slotIds: ids} : {slotId: parsed[0].ref.id};
}
export const saveAvailabilitySlot = onCall(options, r => save(r, false));
export const saveAvailabilitySlots = onCall(options, r => save(r, true));
export const deleteAvailabilitySlot = onCall(options, async r => {
  const uid = uidOf(r); const ref = db().collection("instructors").doc(uid).collection("availability").doc(documentId(r.data?.slotId, "slotId"));
  await db().runTransaction(async tx => { await coach(tx, uid); const slot = (await tx.get(ref)).data(); if (!slot || slot.status !== "available") throw new HttpsError("failed-precondition", "예약되지 않은 시간만 삭제할 수 있습니다."); tx.delete(ref); });
  return {deleted: true};
});
export {rescheduleLesson} from "./lesson_workflow";
import {releaseClosedLesson} from "./lesson_workflow";
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
export const releaseCancelledSlot = onDocumentUpdated({...options, document: "lesson_requests/{id}"}, e => releaseClosedLesson(e.params.id));
