import {createHash} from "node:crypto";
import {getFirestore, Timestamp, FieldPath} from "firebase-admin/firestore";
import {onDocumentWritten, onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {documentId} from "./domain";

const options = {region: "asia-northeast3", maxInstances: 2};
type Data = Record<string, any>;
type Notice = {kind: string; title: string; body: string; targetType: string; targetId: string; targetName?: string};
const db = () => getFirestore();
const text = (value: unknown, fallback = "") => typeof value === "string" ? value.slice(0, 500) : fallback;
const stamp = (value: unknown) => value instanceof Timestamp ? value : Timestamp.fromMillis(0);
const active = (u: Data | undefined) => u?.profileCompleted === true && (u.accountStatus ?? "active") === "active";

// Never overwrite read state or the original event time on event retries/backfill.
async function deliver(uid: unknown, key: string, notice: Notice, at: unknown) {
  if (typeof uid !== "string" || !uid) return;
  const ref = db().collection("users").doc(uid).collection("notifications")
    .doc(createHash("sha256").update(key).digest("hex"));
  await db().runTransaction(async tx => {
    const user = await tx.get(db().collection("users").doc(uid));
    const existing = await tx.get(ref);
    if (!active(user.data()) || existing.exists) return;
    tx.create(ref, {...notice, createdAt: stamp(at), readAt: null});
  });
}

export async function notifyLesson(id: string, after: Data, before?: Data, onlyUid?: string) {
  const participants = [...new Set([after.studentUid, after.instructorUid])].filter(uid => typeof uid === "string" && (!onlyUid || uid === onlyUid));
  const state = text(after.status);
  const labels: Record<string, string> = {pending:"레슨 신청", accepted:"레슨 수락", confirmed:"레슨 예약 확정", completed:"레슨 완료", rejected:"레슨 신청 거절", cancelled:"레슨 취소", expired:"레슨 신청 응답 기한 만료"};
  const at = after.updatedAt ?? after.completedAt ?? after.createdAt;
  for (const uid of participants) {
    const student = uid === after.studentUid;
    const counterpart = text(student ? after.instructorName : after.studentName, student ? "코치" : "수강생");
    const body = state === "pending" ? (student ? `${counterpart} 코치에게 레슨을 신청했습니다.` : `${counterpart} 님이 레슨을 신청했습니다.`)
      : `${counterpart} 님과의 ${text(after.sport, "스포츠")} 레슨 · ${labels[state] ?? state}`;
    if (labels[state] && before?.status !== state) {
      await deliver(uid, `lesson:${id}:${state}`, {kind:"lesson", title:labels[state], body, targetType:"lesson", targetId:id}, at);
    }
    const revision = Number(after.scheduleRevision ?? 0);
    for (const [field, prefix] of [["scheduleProposal", "날짜 변경"], ["completionReview", "참여 확인"]]) {
      const current = after[field], old = before?.[field];
      if (current && (current.status !== old?.status || current.revision !== old?.revision)) {
        const labels: Record<string,string> = {pending:"요청", approved:"승인", rejected:"거절", withdrawn:"철회", expired:"만료", disputed:"이의 제기", reopened:"재협의", confirmed:"확인 완료", resolved:"관리자 확인", cancelled:"취소"};
        await deliver(uid, `${field}:${id}:${current.revision ?? 0}:${current.status}`, {kind:field === "scheduleProposal" ? "schedule" : "lesson", title:`${prefix} ${labels[current.status] ?? current.status}`, body:`${counterpart} 님과의 레슨에서 확인할 내용이 있습니다. 내 레슨을 열어 주세요.`, targetType:"lesson", targetId:id}, after.updatedAt ?? at);
      }
    }
    if (revision > 0 && revision !== Number(before?.scheduleRevision ?? 0)) {
      await deliver(uid, `schedule:${id}:${revision}`, {kind:"schedule", title:"레슨 일정이 변경되었습니다", body:`${counterpart} 님과의 최신 레슨 날짜와 시간을 확인해 주세요.`, targetType:"lesson", targetId:id}, at);
    }
    if (after.paymentStatus && after.paymentStatus !== before?.paymentStatus) {
      const paymentLabels: Record<string,string> = {paid:"결제 완료", partial_refunded:"일부 환불 완료", refunded:"환불 완료", cancelled:"결제 취소"};
      if (paymentLabels[after.paymentStatus]) await deliver(uid, `payment:${id}:${after.paymentStatus}`, {kind:"payment", title:paymentLabels[after.paymentStatus], body:`${counterpart} 님과의 레슨 결제 내역이 변경되었습니다.`, targetType:"lesson", targetId:id}, at);
    }
    const award = after.attendanceBadge;
    if (student && state === "completed" && award && text(award.instructorUid) && text(award.instructorName) && text(award.signatureMove) && !before?.attendanceBadge) {
      await deliver(uid, `badge:${id}`, {kind:"badge", title:"새 뱃지를 획득했습니다", body:`${text(award.signatureMove)} 뱃지가 내 뱃지에 추가되었습니다.`, targetType:"badge", targetId:id}, award.awardedAt ?? after.completedAt ?? at);
    }
  }
}

export async function notifyChat(roomId: string, messageId: string, message: Data, onlyUid?: string) {
  const room = (await db().collection("chat_rooms").doc(roomId).get()).data();
  if (!room || !Array.isArray(room.participantIds) || !room.participantIds.includes(message.senderId)) return;
  const senderName = text(message.senderId === room.coachUid ? room.coachName : room.studentName, "레슨 참여자");
  for (const uid of room.participantIds.filter((uid: string) => uid !== message.senderId && (!onlyUid || uid === onlyUid))) {
    await deliver(uid, `chat:${roomId}:${messageId}`, {kind:"chat", title:`${senderName} 님의 메시지`, body:text(message.text, "새 메시지가 도착했습니다."), targetType:"chat", targetId:roomId, targetName:senderName}, message.createdAt);
  }
}

export async function notifyFeedback(lessonId: string, videoId: string, data: Data, onlyUid?: string) {
  const lesson = (await db().collection("lesson_requests").doc(lessonId).get()).data();
  if (!lesson || ![lesson.studentUid, lesson.instructorUid].includes(data.uploaderUid)) return;
  const recipient = data.uploaderUid === lesson.studentUid ? lesson.instructorUid : lesson.studentUid;
  if (onlyUid && recipient !== onlyUid) return;
  await deliver(recipient, `feedback:${lessonId}:${videoId}`, {kind:"feedback", title:"새 피드백 영상", body:`${text(data.uploaderName, "레슨 참여자")} 님: ${text(data.description, "레슨 영상을 확인해 주세요.")}`, targetType:"lesson", targetId:lessonId}, data.createdAt);
}

export async function notifyCoach(uid: string, data: Data, before?: Data, onlyUid?: string) {
  if (data.status === before?.status) return;
  if (["approved", "rejected"].includes(data.status) && (!onlyUid || onlyUid === uid)) {
    await deliver(uid, `coach:${uid}:${data.status}:${stamp(data.reviewedAt ?? data.updatedAt).toMillis()}`, {kind:"coach", title:data.status === "approved" ? "코치 등록이 승인되었습니다" : "코치 등록 심사 결과", body:data.status === "approved" ? "이제 레슨 신청을 받고 가능 날짜와 시간을 등록할 수 있습니다." : "코치 등록이 반려되었습니다. 등록 정보를 확인해 주세요.", targetType:"profile", targetId:uid}, data.reviewedAt ?? data.updatedAt);
  }
  if (data.status === "pending") {
    const admins = onlyUid ? [await db().collection("users").doc(onlyUid).get()] : (await db().collection("users").where("role", "==", "admin").get()).docs;
    for (const admin of admins.filter(d => d.data()?.role === "admin")) {
      await deliver(admin.id, `coach-request:${uid}:${stamp(data.submittedAt ?? data.createdAt).toMillis()}`, {kind:"coach", title:"코치 등록 승인 요청", body:`${text(data.name, "신청자")} 님의 코치 등록 신청을 확인해 주세요.`, targetType:"admin", targetId:uid}, data.submittedAt ?? data.createdAt);
    }
  }
}

export async function notifyFeedLike(videoId: string, likerUid: string, at: unknown) {
  const video = (await db().collection("feed_videos").doc(videoId).get()).data();
  if (!video || video.userId === likerUid) return;
  await deliver(video.userId, `feed-like:${videoId}:${likerUid}`, {kind:"feed", title:"영상에 좋아요가 도착했습니다", body:text(video.title, "내 레슨 영상을 확인해 주세요."), targetType:"feed", targetId:videoId}, at);
}

export const notifyLessonActivity = onDocumentWritten({...options, document:"lesson_requests/{id}"}, async e => {
  const after = e.data?.after.data();
  if (after) await notifyLesson(e.params.id, after, e.data?.before.data());
});
export const notifyChatMessage = onDocumentCreated({...options, document:"chat_rooms/{room}/messages/{message}"}, async e => {
  if (e.data) await notifyChat(e.params.room, e.params.message, e.data.data());
});
export const notifyLessonFeedback = onDocumentCreated({...options, document:"lesson_requests/{lesson}/feedback_videos/{video}"}, async e => {
  if (e.data) await notifyFeedback(e.params.lesson, e.params.video, e.data.data());
});
export const notifyCoachReview = onDocumentWritten({...options, document:"instructors/{uid}"}, async e => {
  const after = e.data?.after.data();
  if (after) await notifyCoach(e.params.uid, after, e.data?.before.data());
});
export const notifyFeedReaction = onDocumentCreated({...options, document:"feed_videos/{video}/likes/{uid}"}, async e => {
  if (e.data) await notifyFeedLike(e.params.video, e.params.uid, e.data.data().createdAt);
});

// Seed existing activity only for the authenticated owner. Pages keep the
// callable bounded; the client continues until all of that owner's pages end.
export const syncMyNotifications = onCall({...options, timeoutSeconds:120}, async r => {
  if (!r.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const uid = r.auth.uid;
  const user = (await db().collection("users").doc(uid).get()).data();
  if (!active(user)) throw new HttpsError("permission-denied", "가입을 완료한 활성 계정이 필요합니다.");
  const cursor = r.data?.cursor == null ? null : documentId(r.data.cursor, "cursor");
  const category = r.data?.category ?? "lessons";
  if (!["lessons", "chats", "profile"].includes(category) || Object.keys(r.data ?? {}).some(k => !["cursor", "category"].includes(k))) throw new HttpsError("invalid-argument", "알림 요청을 확인해 주세요.");
  if (category === "profile") {
    const ownCoach = (await db().collection("instructors").doc(uid).get()).data();
    if (ownCoach) await notifyCoach(uid, ownCoach, undefined, uid);
    if (user?.role === "admin") {
      const pending = await db().collection("instructors").where("status", "==", "pending").get();
      for (const doc of pending.docs) await notifyCoach(doc.id, doc.data(), undefined, uid);
    }
    return {cursor:null};
  }
  const collection = category === "lessons" ? "lesson_requests" : "chat_rooms";
  let query = db().collection(collection).where("participantIds", "array-contains", uid).orderBy(FieldPath.documentId()).limit(25);
  if (cursor) query = query.startAfter(cursor);
  const page = await query.get();
  for (const doc of page.docs) {
    if (category === "lessons") {
      await notifyLesson(doc.id, doc.data(), undefined, uid);
      const videos = await doc.ref.collection("feedback_videos").get();
      for (const video of videos.docs) await notifyFeedback(doc.id, video.id, video.data(), uid);
    } else {
      const id = doc.data().lastMessageId;
      if (typeof id === "string") {
        const message = await doc.ref.collection("messages").doc(id).get();
        if (message.exists) await notifyChat(doc.id, id, message.data()!, uid);
      }
    }
  }
  return {cursor:page.size === 25 ? page.docs.at(-1)!.id : null};
});
