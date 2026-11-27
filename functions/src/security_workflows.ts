import {getFirestore, FieldValue, Transaction} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {documentId} from "./domain";
import {assertNotBlocked} from './platform_access';
import {feedbackFeedId,feedbackOrigin,validFeedbackFeed} from './feedback_feed';

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

export {requestLesson, requestLessonWithSlot, completeLesson} from "./lesson_workflow";

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
    if(input.liked){
      if(video.visibility==='private'||video.moderationStatus==='hidden'||author.profileCompleted!==true||(author.accountStatus??'active')!=='active'||!await validFeedbackFeed(tx,id,video))throw new HttpsError('failed-precondition','현재 확인할 수 없는 영상입니다.');
      await assertNotBlocked(tx,uid,video.userId);
    }
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
  const target = await db().runTransaction(async tx => {
    const caller = await member(tx, uid); const video = (await tx.get(ref)).data();
    if (!video) throw new HttpsError("not-found", "영상을 찾을 수 없습니다.");
    const owner = video[feedback ? "uploaderUid" : "userId"];
    if (owner !== uid && !(feedback && caller.role === "admin")) throw new HttpsError("permission-denied", "본인 영상 또는 관리자 피드백 정리 권한이 필요합니다.");
    const origin=feedback?{lessonId,videoId,ref}:feedbackOrigin(video);
    const feedRef=feedback?db().doc(`feed_videos/${feedbackFeedId(lessonId,videoId)}`):ref;
    const linkedFeed=feedback?(await tx.get(feedRef)).data():video;
    const sourceRef=origin?.ref;
    const source=sourceRef&&sourceRef.path!==ref.path?(await tx.get(sourceRef)).data():video;
    if(linkedFeed&&linkedFeed.userId!==owner)throw new HttpsError('failed-precondition','영상 연결 정보를 확인해 주세요.');
    if(feedback&&linkedFeed&&(linkedFeed.sourceLessonId!==lessonId||linkedFeed.sourceVideoId!==videoId||linkedFeed.storagePath!==video.storagePath))throw new HttpsError('failed-precondition','영상 연결 정보를 확인해 주세요.');
    if(origin&&source&&source.uploaderUid!==owner)throw new HttpsError('failed-precondition','영상 연결 정보를 확인해 주세요.');
    if(origin&&source&&source.storagePath!==video.storagePath)throw new HttpsError('failed-precondition','영상 연결 정보를 확인해 주세요.');
    const prefix = origin ? `lesson_feedback/${origin.lessonId}/${owner}/` : `videos/${uid}/`;
    if (typeof video.storagePath !== "string" || !video.storagePath.startsWith(prefix) || video.storagePath.slice(prefix.length).includes("/")) throw new HttpsError("failed-precondition", "영상 경로를 확인해 주세요.");
    tx.update(ref, {deleting: true});
    if(sourceRef&&sourceRef.path!==ref.path&&source)tx.update(sourceRef,{deleting:true});
    if(feedRef.path!==ref.path&&linkedFeed)tx.update(feedRef,{deleting:true});
    tx.delete(db().doc(`public_feed_videos/${feedRef.id}`));
    return {path:video.storagePath as string,feedPath:feedRef.path,sourcePath:sourceRef?.path,owner};
  });
  await getStorage().bucket().file(target.path).delete({ignoreNotFound: true});
  const feedRef=db().doc(target.feedPath);
  await db().runTransaction(async tx => {
    const video = (await tx.get(feedRef)).data();if(!video)return;
    const authorRef=db().doc(`users/${target.owner}`),author=(await tx.get(authorRef)).data();
    if(author)tx.update(authorRef,{feedLikeCount:Math.max(0,Number(author.feedLikeCount??0)-Number(video.likes??0))});
    tx.update(feedRef,{likes:0});
  });
  await db().recursiveDelete(feedRef.collection('likes'));
  await db().runTransaction(async tx=>{
    const feed=(await tx.get(feedRef)).data();
    const sourceRef=target.sourcePath?db().doc(target.sourcePath):null;
    const source=sourceRef?(await tx.get(sourceRef)).data():null;
    if(feed?.deleting)tx.delete(feedRef);
    if(sourceRef&&source?.deleting)tx.delete(sourceRef);
  });
  return {deleted: true};
});
