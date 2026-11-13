import {getFirestore, FieldValue, Timestamp, Transaction} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {documentId} from "./domain";
import {supportedSports} from "./models";

const options = {region: "asia-northeast3", maxInstances: 2};
const stamp = () => FieldValue.serverTimestamp();
const db = () => getFirestore();
async function member(tx: Transaction, uid: string, complete = true) {
  const data = (await tx.get(db().collection("users").doc(uid))).data();
  if (!data || (data.accountStatus ?? "active") !== "active" || (complete && data.profileCompleted !== true)) {
    throw new HttpsError("permission-denied", "활성 가입 완료 계정이 필요합니다.");
  }
  return data;
}
function uidOf(request: CallableRequest) {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  return request.auth.uid;
}
function inputOf(request: CallableRequest, allowed: string[]) {
  const d = request.data;
  if (!d || typeof d !== "object" || Array.isArray(d) || Object.keys(d).some(k => !allowed.includes(k))) throw new HttpsError("invalid-argument", "요청 항목을 확인해 주세요.");
  return d as Record<string, unknown>;
}
function select(data: FirebaseFirestore.DocumentData, keys: string[]) {
  return Object.fromEntries(keys.filter(k => data[k] !== undefined).map(k => [k, data[k]]));
}
function nonempty(value: unknown): string | undefined { return typeof value === "string" && value.trim() ? value.trim() : undefined; }

// Read current documents inside the transaction: trigger retries/out-of-order delivery
// must never republish an old approved profile after suspension/rejection.
export async function projectPublicProfile(uid: string) {
  await db().runTransaction(async tx => {
    const user = (await tx.get(db().collection("users").doc(uid))).data();
    const coach = (await tx.get(db().collection("instructors").doc(uid))).data();
    const userRef = db().collection("public_users").doc(uid);
    const coachRef = db().collection("public_instructors").doc(uid);
    const eligible = user && user.profileCompleted === true && (user.accountStatus ?? "active") === "active";
    if (!eligible) { tx.delete(userRef); tx.delete(coachRef); return; }
    tx.set(userRef, {uid, ...select(user, ["name", "role", "profileImage", "targetTier", "aspirations", "videoUrl", "lessonCount", "feedLikeCount", "signatureMove", "signatureBadgeId", "signatureBadgeColorIndex"])});
    if (coach?.status === "approved" && user.role === "coach") {
      tx.set(coachRef, select(coach, ["uid", "userId", "name", "sport", "lessonLevel", "career", "rating", "status", "signatureMove", "signatureBadgeId", "signatureBadgeColorIndex"]));
    } else tx.delete(coachRef);
  });
}
export const projectUserPublicProfile = onDocumentWritten({...options, document: "users/{uid}"}, e => projectPublicProfile(e.params.uid));
export const projectInstructorPublicProfile = onDocumentWritten({...options, document: "instructors/{uid}"}, e => projectPublicProfile(e.params.uid));

async function createRequest(request: CallableRequest, withSlot: boolean) {
  const uid = uidOf(request);
  const input = inputOf(request, withSlot ? ["instructorId", "slotId"] : ["instructorId"]);
  const coachUid = documentId(input.instructorId, "instructorId");
  if (coachUid === uid) throw new HttpsError("invalid-argument", "본인에게 신청할 수 없습니다.");
  const ref = db().collection("lesson_requests").doc();
  await db().runTransaction(async tx => {
    const student = await member(tx, uid);
    const coach = await member(tx, coachUid);
    const profile = (await tx.get(db().collection("instructors").doc(coachUid))).data();
    const pair = db().collection("active_lesson_requests").doc(`${coachUid}_${uid}`);
    const existing = await tx.get(pair);
    const slotRef = withSlot ? db().collection("instructors").doc(coachUid).collection("availability").doc(documentId(input.slotId, "slotId")) : null;
    const slot = slotRef ? (await tx.get(slotRef)).data() : null;
    if (!["student", "admin"].includes(student.role) || coach.role !== "coach" || profile?.status !== "approved" || profile.uid !== coachUid || !(supportedSports as readonly string[]).includes(profile.sport)) throw new HttpsError("permission-denied", "신청 가능한 수강생과 승인 코치가 필요합니다.");
    if (existing.exists) throw new HttpsError("already-exists", "진행 중인 레슨이 있습니다.");
    if (slotRef && (!slot || slot.status !== "available" || !(slot.startAt instanceof Timestamp) || slot.startAt.toMillis() <= Date.now())) throw new HttpsError("failed-precondition", "예약 가능한 시간이 아닙니다.");
    const ids = [uid, coachUid].sort();
    tx.create(ref, {instructorId: coachUid, instructorUid: coachUid, instructorName: profile.name,
      studentUid: uid, studentName: student.name, participantIds: ids, sport: profile.sport,
      ...select(profile, ["signatureMove", "signatureBadgeId", "signatureBadgeColorIndex"]),
      status: "pending", paymentRequired: false, isInstructorInitiated: false, createdAt: stamp(),
      ...(slot ? {slotId: slotRef!.id, scheduledStartAt: slot.startAt, scheduledEndAt: slot.endAt} : {})});
    tx.create(pair, {requestId: ref.id, participantIds: ids});
    if (slotRef) tx.update(slotRef, {status: "booked", lessonId: ref.id, updatedAt: stamp()});
  });
  return {lessonId: ref.id};
}
export const requestLesson = onCall(options, r => createRequest(r, false));
export const requestLessonWithSlot = onCall(options, r => createRequest(r, true));

export const completeLesson = onCall(options, async request => {
  const uid = uidOf(request); const input = inputOf(request, ["lessonId", "reviewScore", "feedback", "signatureMove"]);
  const id = documentId(input.lessonId, "lessonId"); const score = input.reviewScore; const feedback = input.feedback;
  if (typeof score !== "number" || !Number.isFinite(score) || score < 1 || score > 5 || typeof feedback !== "string" || feedback.length > 1000) throw new HttpsError("invalid-argument", "평가와 피드백을 확인해 주세요.");
  await db().runTransaction(async tx => {
    const caller = await member(tx, uid);
    const ref = db().collection("lesson_requests").doc(id); const lesson = (await tx.get(ref)).data();
    const profile = (await tx.get(db().collection("instructors").doc(uid))).data();
    if (!lesson || lesson.instructorUid !== uid || caller.role !== "coach" || profile?.status !== "approved") throw new HttpsError("permission-denied", "담당 승인 코치만 완료할 수 있습니다.");
    if (lesson.paymentRequired === true || Object.hasOwn(lesson, "price") || Object.hasOwn(lesson, "paymentId")) throw new HttpsError("failed-precondition", "유료 레슨 완료 절차를 이용해 주세요.");
    if (lesson.status === "completed") return;
    if (lesson.status !== "accepted") throw new HttpsError("failed-precondition", "수락한 레슨만 완료할 수 있습니다.");
    const student = await member(tx, lesson.studentUid);
    const badgeId = nonempty(profile?.signatureBadgeId) ?? nonempty(caller.signatureBadgeId) ?? nonempty(lesson.signatureBadgeId);
    const badge = badgeId ? (await tx.get(db().collection("signature_badges").doc(badgeId))).data() : undefined;
    if (badgeId && !badge) throw new HttpsError("failed-precondition", "선택한 시그니처 뱃지를 다시 등록해 주세요.");
    const signature = nonempty(badge?.name) ?? nonempty(profile?.signatureMove) ?? nonempty(caller.signatureMove) ?? nonempty(lesson.signatureMove);
    if (typeof signature !== "string" || !signature.trim() || signature.length > 40 || (nonempty(input.signatureMove) && nonempty(input.signatureMove) !== signature)) throw new HttpsError("failed-precondition", "코치 시그니처 기술을 확인해 주세요.");
    const instructorName = nonempty(lesson.instructorName) ?? nonempty(profile?.name) ?? nonempty(caller.name) ?? "코치";
    const sport = nonempty(lesson.sport) ?? nonempty(profile?.sport) ?? nonempty(caller.sport) ?? "";
    const color = badge?.colorIndex ?? profile?.signatureBadgeColorIndex ?? caller.signatureBadgeColorIndex ?? lesson.signatureBadgeColorIndex;
    tx.update(ref, {status: "completed", reviewScore: score, reviewFeedback: feedback,
      attendanceBadge: {instructorUid: uid, instructorName, sport, signatureMove: signature,
        ...(badgeId ? {signatureBadgeId: badgeId} : {}),
        ...(typeof color === "number" ? {signatureBadgeColorIndex: color} : {}),
        awardedAt: stamp(), verifiedBy: uid}, completedAt: stamp(), updatedAt: stamp()});
    tx.update(db().collection("users").doc(lesson.studentUid), {lastCompletedLessonId: id, lessonCount: FieldValue.increment(1), reviewScores: [...(student.reviewScores ?? []), score], ...(lesson.isInstructorInitiated ? {teacherMatchCount: FieldValue.increment(1)} : {})});
    tx.delete(db().collection("active_lesson_requests").doc(`${uid}_${lesson.studentUid}`));
  });
  return {lessonId: id, status: "completed"};
});

export const setFeedLiked = onCall(options, async request => {
  const uid = uidOf(request); const input = inputOf(request, ["videoId", "liked"]);
  const id = documentId(input.videoId, "videoId"); if (typeof input.liked !== "boolean") throw new HttpsError("invalid-argument", "좋아요 상태를 확인해 주세요.");
  await db().runTransaction(async tx => {
    await member(tx, uid);
    const ref = db().collection("feed_videos").doc(id); const video = (await tx.get(ref)).data();
    const likeRef = ref.collection("likes").doc(uid); const like = await tx.get(likeRef);
    if (!video || video.deleting === true || typeof video.userId !== "string" || video.userId === uid) throw new HttpsError("failed-precondition", "다른 회원의 영상만 좋아요를 누를 수 있습니다.");
    const author = (await tx.get(db().collection("users").doc(video.userId))).data();
    if (!author) throw new HttpsError("failed-precondition", "영상 작성자의 계정이 없습니다.");
    if (like.exists === input.liked) return;
    const delta = input.liked ? 1 : -1;
    tx.update(ref, {likes: Math.max(0, (video.likes ?? 0) + delta)});
    tx.update(db().collection("users").doc(video.userId), {lastFeedLikeVideoId: id, feedLikeCount: Math.max(0, (author.feedLikeCount ?? 0) + delta)});
    if (input.liked) tx.create(likeRef, {userId: uid, createdAt: stamp()}); else tx.delete(likeRef);
  });
  return {liked: input.liked};
});

export const deleteVideo = onCall(options, async request => {
  const uid = uidOf(request); const input = inputOf(request, ["kind", "videoId", "lessonId"]);
  const videoId = documentId(input.videoId, "videoId");
  const feedback = input.kind === "feedback";
  if (!feedback && input.kind !== "feed") throw new HttpsError("invalid-argument", "영상 종류를 확인해 주세요.");
  const lessonId = feedback ? documentId(input.lessonId, "lessonId") : "";
  const ref = feedback ? db().collection("lesson_requests").doc(lessonId).collection("feedback_videos").doc(videoId) : db().collection("feed_videos").doc(videoId);
  const path = await db().runTransaction(async tx => {
    const caller = await member(tx, uid); const video = (await tx.get(ref)).data();
    if (!video) throw new HttpsError("not-found", "영상을 찾을 수 없습니다.");
    const owner = video[feedback ? "uploaderUid" : "userId"];
    if (owner !== uid && !(feedback && caller.role === "admin")) throw new HttpsError("permission-denied", "본인 영상 또는 관리자 피드백 정리 권한이 필요합니다.");
    const prefix = feedback ? `lesson_feedback/${lessonId}/${owner}/` : `videos/${uid}/`;
    if (typeof video.storagePath !== "string" || !video.storagePath.startsWith(prefix) || video.storagePath.slice(prefix.length).includes("/")) throw new HttpsError("failed-precondition", "영상 경로를 확인해 주세요.");
    tx.update(ref, {deleting: true});
    return video.storagePath as string;
  });
  await getStorage().bucket().file(path).delete({ignoreNotFound: true});
  await db().runTransaction(async tx => {
    const video = (await tx.get(ref)).data();
    if (!video) return;
    if (!feedback) {
      const authorRef = db().collection("users").doc(uid);
      const author = (await tx.get(authorRef)).data();
      if (author) tx.update(authorRef, {feedLikeCount: Math.max(0, (author.feedLikeCount ?? 0) - (video.likes ?? 0))});
    }
    tx.delete(ref);
  });
  await db().recursiveDelete(ref);
  return {deleted: true};
});
