import {createHash} from 'node:crypto';
import {getFirestore,FieldValue,Transaction,DocumentData} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {onCall,HttpsError} from 'firebase-functions/v2/https';
import {onDocumentDeleted} from 'firebase-functions/v2/firestore';
import {documentId} from './domain';
import {authenticatedInput,activeMember} from './platform_access';
import {publicFeedData,isPublicFeed} from './feed_projection';

const options={region:'asia-northeast3',maxInstances:2,timeoutSeconds:120};
const db=()=>getFirestore(),stamp=()=>FieldValue.serverTimestamp();
export const feedbackFeedId=(lessonId:string,videoId:string)=>'feedback_'+createHash('sha256').update(lessonId+'/'+videoId).digest('hex').slice(0,48);
const feedbackRef=(lessonId:string,videoId:string)=>db().doc(`lesson_requests/${lessonId}/feedback_videos/${videoId}`);
export function feedbackOrigin(video:DocumentData){
  if(video.sourceType!=='lesson_feedback')return null;
  const lessonId=documentId(video.sourceLessonId,'lessonId'),videoId=documentId(video.sourceVideoId,'videoId');
  return {lessonId,videoId,ref:feedbackRef(lessonId,videoId)};
}
export async function validFeedbackFeed(tx:Transaction,id:string,video:DocumentData,publicOnly=true){
  const origin=feedbackOrigin(video);if(!origin)return true;
  const source=(await tx.get(origin.ref)).data();
  return id===feedbackFeedId(origin.lessonId,origin.videoId)&&!!source&&!source.deleting&&source.uploaderUid===video.userId&&source.storagePath===video.storagePath
    &&source.publicFeedId===id&&(!publicOnly||(source.visibility==='public'&&source.moderationStatus!=='hidden'));
}
function mediaPath(path:unknown,lessonId:string,uid:string){
  const prefix=`lesson_feedback/${lessonId}/${uid}/`;
  if(typeof path!=='string'||!path.startsWith(prefix)||!path.slice(prefix.length)||path.slice(prefix.length).includes('/'))throw new HttpsError('invalid-argument','영상 경로를 확인해 주세요.');
  return path;
}
async function uploadedMedia(path:string){
  let meta;
  try{[meta]=await getStorage().bucket().file(path).getMetadata();}
  catch(e){if(Number((e as {code?:unknown}).code)===404)throw new HttpsError('failed-precondition','영상 업로드가 완료된 뒤 다시 시도해 주세요.');throw e;}
  const size=Number(meta.size);
  if(!Number.isFinite(size)||size<=0||size>100*1024*1024||!meta.contentType?.startsWith('video/'))throw new HttpsError('failed-precondition','100MB 이하의 업로드된 영상만 게시할 수 있습니다.');
}
function text(value:unknown,max:number,label:string,empty=true){
  if(typeof value!=='string'||value.trim().length>max||(!empty&&!value.trim()))throw new HttpsError('invalid-argument',`${label} 내용을 확인해 주세요.`);
  return value.trim();
}
export const registerLessonFeedback=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['lessonId','videoId','storagePath','title','description']);
  const lessonId=documentId(data.lessonId,'lessonId'),videoId=documentId(data.videoId,'videoId');
  const path=mediaPath(data.storagePath,lessonId,uid),title=text(data.title,120,'제목',false),description=text(data.description,2000,'설명');
  await uploadedMedia(path);
  const id=feedbackFeedId(lessonId,videoId),sourceRef=feedbackRef(lessonId,videoId),feedRef=db().doc(`feed_videos/${id}`);
  return db().runTransaction(async tx=>{
    const user=await activeMember(tx,uid),lesson=(await tx.get(db().doc(`lesson_requests/${lessonId}`))).data();
    const existing=(await tx.get(sourceRef)).data(),feed=(await tx.get(feedRef)).data();
    if((await tx.get(db().doc('app_config/features'))).data()?.videoUploadsEnabled===false)throw new HttpsError('failed-precondition','영상 등록이 잠시 중지되어 있습니다.');
    if(!lesson||![lesson.studentUid,lesson.instructorUid].includes(uid)||!['accepted','confirmed','completed'].includes(lesson.status))throw new HttpsError('permission-denied','수락·진행·완료된 레슨의 참여자만 영상을 등록할 수 있습니다.');
    if(existing){
      if(existing.uploaderUid!==uid||existing.storagePath!==path||existing.deleting)throw new HttpsError('failed-precondition','이미 사용 중인 영상 정보입니다.');
      return {videoId,feedId:id,visibility:existing.visibility??'private'};
    }
    if(feed)throw new HttpsError('failed-precondition','이전 영상 정리가 진행 중입니다. 잠시 후 다시 시도해 주세요.');
    const createdAt=stamp(),video={userId:uid,userName:user.name??'회원',title,description,storagePath:path,videoUrl:path,likes:0,createdAt,visibility:'public',sourceType:'lesson_feedback',sourceLessonId:lessonId,sourceVideoId:videoId};
    tx.create(sourceRef,{uploaderUid:uid,uploaderName:user.name??'회원',lessonId,storagePath:path,title,description,createdAt,visibility:'public',publicFeedId:id});
    tx.create(feedRef,video);tx.set(db().doc(`public_feed_videos/${id}`),publicFeedData(video,user));
    return {videoId,feedId:id,visibility:'public'};
  });
});
export const setFeedbackVisibility=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['lessonId','videoId','isPublic']);
  const lessonId=documentId(data.lessonId,'lessonId'),videoId=documentId(data.videoId,'videoId');
  if(typeof data.isPublic!=='boolean')throw new HttpsError('invalid-argument','공개 범위를 확인해 주세요.');
  const sourceRef=feedbackRef(lessonId,videoId),id=feedbackFeedId(lessonId,videoId),feedRef=db().doc(`feed_videos/${id}`);
  const before=(await sourceRef.get()).data();
  if(!before||before.uploaderUid!==uid)throw new HttpsError('permission-denied','영상을 올린 회원만 공개 범위를 변경할 수 있습니다.');
  const path=mediaPath(before.storagePath,lessonId,uid);if(data.isPublic)await uploadedMedia(path);
  return db().runTransaction(async tx=>{
    const user=await activeMember(tx,uid),source=(await tx.get(sourceRef)).data(),feed=(await tx.get(feedRef)).data();
    const lesson=(await tx.get(db().doc(`lesson_requests/${lessonId}`))).data();
    if(data.isPublic&&(await tx.get(db().doc('app_config/features'))).data()?.videoUploadsEnabled===false)throw new HttpsError('failed-precondition','영상 게시가 잠시 중지되어 있습니다.');
    if(!source||source.uploaderUid!==uid||source.deleting||source.storagePath!==path||!lesson||![lesson.studentUid,lesson.instructorUid].includes(uid))throw new HttpsError('permission-denied','현재 공개 범위를 변경할 수 없습니다.');
    if(feed?.deleting||(feed&&feed.userId!==uid))throw new HttpsError('failed-precondition','영상 정리가 진행 중입니다.');
    if(data.isPublic&&(feed?.moderationStatus==='hidden'||source.moderationStatus==='hidden'))throw new HttpsError('failed-precondition','운영진이 숨긴 영상은 다시 게시할 수 없습니다.');
    const visibility=data.isPublic?'public':'private';
    const video={...feed,userId:uid,userName:user.name??'회원',title:source.title??`${lesson.sport??'레슨'} 피드백`,description:source.description??'',storagePath:path,videoUrl:path,likes:feed?.likes??0,createdAt:feed?.createdAt??source.createdAt??stamp(),visibility,sourceType:'lesson_feedback',sourceLessonId:lessonId,sourceVideoId:videoId};
    tx.update(sourceRef,{visibility,publicFeedId:id});tx.set(feedRef,video);
    if(isPublicFeed(video,user))tx.set(db().doc(`public_feed_videos/${id}`),publicFeedData(video,user));else tx.delete(db().doc(`public_feed_videos/${id}`));
    return {feedId:id,visibility};
  });
});
export async function removeDeletedFeedback(lessonId:string,videoId:string){
  const id=feedbackFeedId(lessonId,videoId),ref=db().doc(`feed_videos/${id}`);
  const marked=await db().runTransaction(async tx=>{
    const source=await tx.get(feedbackRef(lessonId,videoId)),feed=(await tx.get(ref)).data();
    if(source.exists||!feed)return false;
    const authorRef=db().doc(`users/${feed.userId}`),author=(await tx.get(authorRef)).data();
    if(author)tx.update(authorRef,{feedLikeCount:Math.max(0,Number(author.feedLikeCount??0)-Number(feed.likes??0))});
    tx.update(ref,{deleting:true,likes:0});tx.delete(db().doc(`public_feed_videos/${id}`));return true;
  });
  if(!marked)return;
  await db().recursiveDelete(ref.collection('likes'));
  await db().runTransaction(async tx=>{if((await tx.get(ref)).data()?.deleting)tx.delete(ref);});
}
export const removeFeedbackFeed=onDocumentDeleted({...options,retry:true,document:'lesson_requests/{lessonId}/feedback_videos/{videoId}'},e=>removeDeletedFeedback(e.params.lessonId,e.params.videoId));
