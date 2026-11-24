import {getFirestore, FieldValue, FieldPath, Timestamp, Query} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';
import {onCall,HttpsError} from 'firebase-functions/v2/https';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {authenticatedInput,activeMember} from './platform_access';

const options={region:'asia-northeast3',maxInstances:2,timeoutSeconds:120};
const db=()=>getFirestore(),stamp=()=>FieldValue.serverTimestamp();
type Data=Record<string,any>;
export const requestAccountDeletion=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['confirmation']);
  if(data.confirmation!=='회원탈퇴')throw new HttpsError('invalid-argument','회원탈퇴 확인 문구를 입력해 주세요.');
  const authTime=Number(r.auth!.token.auth_time);
  if(!Number.isFinite(authTime)||authTime*1000<Date.now()-300000||authTime*1000>Date.now()+60000)throw new HttpsError('failed-precondition','계정 보호를 위해 다시 인증한 뒤 탈퇴해 주세요.');
  await db().runTransaction(async tx=>{
    const ref=db().doc(`account_deletions/${uid}`),existing=(await tx.get(ref)).data();
    if(existing)return;
    const user=await activeMember(tx,uid,false);
    if(user.role==='admin')throw new HttpsError('failed-precondition','관리자 계정은 다른 관리자에게 운영 권한을 이관한 뒤 처리해 주세요.');
    const lessons=await tx.get(db().collection('lesson_requests').where('participantIds','array-contains',uid));
    if(lessons.docs.some(d=>['pending','accepted','confirmed'].includes(d.data().status)))throw new HttpsError('failed-precondition','대기·진행 중인 레슨을 먼저 취소하거나 완료해 주세요.');
    // The same calendar lock used by booking prevents a new lesson racing deletion.
    const lock=db().doc(`lesson_calendar_locks/${uid}`);await tx.get(lock);
    tx.update(db().doc(`users/${uid}`),{accountStatus:'deleting',pushEnabled:false,updatedAt:stamp()});
    tx.set(lock,{revision:FieldValue.increment(1),updatedAt:stamp()},{merge:true});
    tx.create(ref,{uid,role:user.role,status:'pending',phase:0,createdAt:stamp(),requestedBy:uid});
  });
  return {status:'pending'};
});

type CleanupAdapters={disableAuth:(uid:string)=>Promise<void>;deleteAuth:(uid:string)=>Promise<void>;deleteFile:(path:string)=>Promise<void>;deletePrefix:(prefix:string)=>Promise<boolean>};
async function ignoreMissing(task:()=>Promise<unknown>){try{await task();}catch(e){if((e as {code?:string}).code!=='auth/user-not-found')throw e;}}
const adapters:CleanupAdapters={
  disableAuth:uid=>ignoreMissing(async()=>{await getAuth().updateUser(uid,{disabled:true});await getAuth().revokeRefreshTokens(uid);}),
  deleteAuth:uid=>ignoreMissing(()=>getAuth().deleteUser(uid)),
  deleteFile:async path=>{await getStorage().bucket().file(path).delete({ignoreNotFound:true});},
  deletePrefix:async prefix=>{const [files]=await getStorage().bucket().getFiles({prefix,maxResults:50,autoPaginate:false});for(const file of files)await file.delete({ignoreNotFound:true});return files.length===0;}
};
async function redactNotices(other:string,targetId:string){
  const notices=await db().collection(`users/${other}/notifications`).where('targetId','==',targetId).get();
  for(let offset=0;offset<notices.size;offset+=400){const batch=db().batch();for(const d of notices.docs.slice(offset,offset+400))batch.update(d.ref,{title:'이전 활동 알림',body:'탈퇴한 회원과의 이전 활동입니다.',targetName:'탈퇴한 회원'});await batch.commit();}
}
async function pagedIdentity(query:Query,cursor:string|undefined,handle:(doc:FirebaseFirestore.QueryDocumentSnapshot)=>Promise<void>){
  let q=query.orderBy(FieldPath.documentId()).limit(50);if(cursor)q=q.startAfter(cursor);
  const page=await q.get();for(const doc of page.docs)await handle(doc);
  return {done:page.size<50,cursor:page.docs.at(-1)?.id};
}
async function cleanupStep(uid:string,job:Data,io:CleanupAdapters):Promise<{done:boolean;cursor?:string}>{
  const phase=Number(job.phase??0);
  if(phase===0){await io.disableAuth(uid);return {done:true};}
  if(phase===1||phase===2)return {done:await io.deletePrefix(`${phase===1?'videos':'coach_documents'}/${uid}/`)};
  if(phase===3){
    const page=await db().collectionGroup('feedback_videos').where('uploaderUid','==',uid).limit(50).get();
    for(const doc of page.docs){const d=doc.data(),lesson=doc.ref.parent.parent;
      if(lesson?.parent.id==='lesson_requests'&&typeof d.storagePath==='string'&&d.storagePath.startsWith(`lesson_feedback/${lesson.id}/${uid}/`))await io.deleteFile(d.storagePath);
      await doc.ref.delete();
    }return {done:page.empty};
  }
  if(phase===4){
    const page=await db().collection('feed_videos').where('userId','==',uid).limit(50).get();
    for(const doc of page.docs){await db().doc(`public_feed_videos/${doc.id}`).delete();await db().recursiveDelete(doc.ref);}return {done:page.empty};
  }
  if(phase===5){
    const page=await db().collectionGroup('likes').where('userId','==',uid).limit(100).get();
    for(const d of page.docs){const feed=d.ref.parent.parent;
      if(feed?.parent.id!=='feed_videos'){continue;}
      await db().runTransaction(async tx=>{
        const like=await tx.get(d.ref),video=(await tx.get(feed)).data();
        const authorRef=typeof video?.userId==='string'?db().doc(`users/${video.userId}`):null;
        const author=authorRef?(await tx.get(authorRef)).data():null;
        if(!like.exists)return;
        tx.delete(d.ref);
        if(video)tx.update(feed,{likes:Math.max(0,Number(video.likes??0)-1)});
        if(author&&authorRef)tx.update(authorRef,{feedLikeCount:Math.max(0,Number(author.feedLikeCount??0)-1)});
      });
    }return {done:page.empty};
  }
  if(phase===6){
    const page=await db().collectionGroup('messages').where('senderId','==',uid).limit(100).get();
    for(const doc of page.docs){const room=doc.ref.parent.parent;
      if(room?.parent.id!=='chat_rooms'){continue;}
      await db().runTransaction(async tx=>{const data=(await tx.get(room)).data();tx.delete(doc.ref);if(data?.lastMessageId===doc.id)tx.update(room,{lastMessage:'탈퇴한 회원의 메시지입니다.',lastMessageId:FieldValue.delete()});});
    }return {done:page.empty};
  }
  if(phase===7)return pagedIdentity(db().collection('lesson_requests').where('participantIds','array-contains',uid),job.cursor,async doc=>{
    const d=doc.data(),change:Data={};
    if(d.studentUid===uid)change.studentName='탈퇴한 회원';
    if(d.instructorUid===uid){change.instructorName='탈퇴한 코치';if(d.attendanceBadge)change['attendanceBadge.instructorName']='탈퇴한 코치';if(d.completionReview?.attendanceBadge)change['completionReview.attendanceBadge.instructorName']='탈퇴한 코치';}
    if(Object.keys(change).length)await doc.ref.update(change);
    const history=await doc.ref.collection('schedule_changes').where('changedBy','==',uid).get();
    for(const h of history.docs)await h.ref.update({changedByName:'탈퇴한 회원'});
    for(const other of [d.studentUid,d.instructorUid].filter(v=>typeof v==='string'&&v!==uid))await redactNotices(other,doc.id);
  });
  if(phase===8)return pagedIdentity(db().collection('chat_rooms').where('participantIds','array-contains',uid),job.cursor,async doc=>{
    const d=doc.data();await doc.ref.update(d.studentUid===uid?{studentName:'탈퇴한 회원'}:{coachName:'탈퇴한 코치'});
    for(const other of (d.participantIds??[]).filter((v:unknown)=>typeof v==='string'&&v!==uid))await redactNotices(other,doc.id);
  });
  const reportFields=['reporterUid','reporterId','reportedUid','reportedUserId'];
  if(phase>=9&&phase<=12)return pagedIdentity(db().collection('reports').where(reportFields[phase-9],'==',uid),job.cursor,async doc=>{await doc.ref.update(phase<11?{reporterEmail:FieldValue.delete()}:{reportedUserName:'탈퇴한 회원'});});
  if(phase===13){
    const incomingBlocks=await db().collectionGroup('members').where('targetUid','==',uid).limit(100).get();
    if(!incomingBlocks.empty){
      const batch=db().batch();
      for(const doc of incomingBlocks.docs)batch.delete(doc.ref);
      await batch.commit();return {done:false};
    }
    const devices=await db().collection('push_devices').where('uid','==',uid).get();for(const doc of devices.docs)await doc.ref.delete();
    for(const collection of ['instructors','public_instructors','public_users','coach_document_uploads','user_blocks','community_rate_limits'])await db().recursiveDelete(db().doc(`${collection}/${uid}`));
    // Keep the blocked root document present: a still-valid old Auth token
    // must never be able to race deletion by recreating a fresh active profile.
    for(const collection of await db().doc(`users/${uid}`).listCollections())await db().recursiveDelete(collection);
    await db().doc(`users/${uid}`).set({uid,role:job.role??'student',name:'탈퇴한 회원',accountStatus:'deleted',profileCompleted:false,deletedAt:stamp()});
    return {done:true};
  }
  if(phase===14){await io.deleteAuth(uid);return {done:true};}
  return {done:true};
}
export async function processAccountDeletion(uid:string,io:CleanupAdapters=adapters){
  const ref=db().doc(`account_deletions/${uid}`),now=Date.now();
  const claimed=await db().runTransaction(async tx=>{
    const job=(await tx.get(ref)).data();if(!job||job.status==='done'||job.leaseUntil?.toMillis()>now)return false;
    tx.update(ref,{status:'pending',leaseUntil:Timestamp.fromMillis(now+115000),attemptedAt:stamp()});return true;
  });
  if(!claimed)return;
  try{
    while(Date.now()-now<80000){
      const job=(await ref.get()).data()!;
      if(Number(job.phase??0)>14){await ref.update({status:'done',completedAt:stamp(),leaseUntil:Timestamp.fromMillis(0)});return;}
      const result=await cleanupStep(uid,job,io);
      await ref.update({phase:Number(job.phase??0)+(result.done?1:0),cursor:result.done?FieldValue.delete():result.cursor??FieldValue.delete(),updatedAt:stamp()});
    }
    await ref.update({leaseUntil:Timestamp.fromMillis(0)});
  }catch(error){await ref.update({leaseUntil:Timestamp.fromMillis(0),lastErrorAt:stamp()});throw error;}
}
export const beginAccountCleanup=onDocumentCreated({...options,retry:true,document:'account_deletions/{uid}'},e=>processAccountDeletion(e.params.uid));
export const retryAccountCleanup=onSchedule({...options,schedule:'every 5 minutes',timeZone:'Asia/Seoul'},async()=>{
  const jobs=await db().collection('account_deletions').where('status','==','pending').limit(30).get();
  for(const job of jobs.docs){try{await processAccountDeletion(job.id);}catch{console.error('Account cleanup will retry',{uid:job.id});}}
});
