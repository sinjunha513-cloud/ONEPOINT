import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {onCall,HttpsError} from 'firebase-functions/v2/https';
import {authenticatedInput,activeMember,assertNotBlocked} from './platform_access';
import {documentId} from './domain';

export const getMediaPlayback=onCall({region:'asia-northeast3',maxInstances:2},async r=>{
  const {uid,data}=authenticatedInput(r,['kind','videoId','lessonId']);
  const path=await authorizedMediaPath(uid,data);
  const expiresAt=Date.now()+15*60000;
  const [url]=await getStorage().bucket().file(path).getSignedUrl({version:'v4',action:'read',expires:expiresAt});
  return {url,expiresAt};
});
export async function authorizedMediaPath(uid:string,data:Record<string,unknown>){
  const id=documentId(data.videoId,'videoId'),feedback=data.kind==='feedback';
  if(!feedback&&data.kind!=='feed')throw new HttpsError('invalid-argument','영상 종류를 확인해 주세요.');
  const lessonId=feedback?documentId(data.lessonId,'lessonId'):'';
  return getFirestore().runTransaction(async tx=>{
    const user=await activeMember(tx,uid);
    const ref=feedback?getFirestore().doc(`lesson_requests/${lessonId}/feedback_videos/${id}`):getFirestore().doc(`feed_videos/${id}`);
    const video=(await tx.get(ref)).data();
    if(!video||video.deleting)throw new HttpsError('not-found','영상을 찾을 수 없습니다.');
    const owner=feedback?video.uploaderUid:video.userId;
    if(feedback){
      const lesson=(await tx.get(getFirestore().doc(`lesson_requests/${lessonId}`))).data();
      if(user.role!=='admin'&&![lesson?.studentUid,lesson?.instructorUid].includes(uid))throw new HttpsError('permission-denied','레슨 참여자만 확인할 수 있습니다.');
    }else if(user.role!=='admin'&&uid!==owner){
      if(video.moderationStatus==='hidden')throw new HttpsError('permission-denied','현재 확인할 수 없는 영상입니다.');
      await activeMember(tx,owner);await assertNotBlocked(tx,uid,owner);
    }
    const prefix=feedback?`lesson_feedback/${lessonId}/${owner}/`:`videos/${owner}/`;
    if(typeof video.storagePath!=='string'||!video.storagePath.startsWith(prefix)||video.storagePath.slice(prefix.length).includes('/'))throw new HttpsError('failed-precondition','영상 경로를 확인해 주세요.');
    return video.storagePath as string;
  });
}
