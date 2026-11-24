import {getFirestore, FieldValue, Transaction} from 'firebase-admin/firestore';
import {HttpsError, onCall} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {documentId} from './domain';
import {activeMember, authenticatedInput, requiredReason} from './platform_access';
import {deliverNotification} from './notifications';

const options={region:'asia-northeast3',maxInstances:2};
const db=()=>getFirestore(), stamp=()=>FieldValue.serverTimestamp();
export const setUserBlocked=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['targetUid','blocked']);
  const target=documentId(data.targetUid,'targetUid');
  if(target===uid||typeof data.blocked!=='boolean')throw new HttpsError('invalid-argument','차단할 회원을 확인해 주세요.');
  await db().runTransaction(async tx=>{
    await activeMember(tx,uid);
    const user=(await tx.get(db().doc(`users/${target}`))).data();
    if(data.blocked&&!user)throw new HttpsError('not-found','회원을 찾을 수 없습니다.');
    const ref=db().doc(`user_blocks/${uid}/members/${target}`);
    if(data.blocked)tx.set(ref,{targetUid:target,name:user?.name??'회원',createdAt:stamp()});else tx.delete(ref);
  });
  return {blocked:data.blocked};
});
export const submitReport=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['targetType','targetId','reason','details','requestId']);
  const targetId=documentId(data.targetId,'targetId'), requestId=documentId(data.requestId,'requestId');
  if(!['user','feed'].includes(data.targetType as string))throw new HttpsError('invalid-argument','신고 대상을 확인해 주세요.');
  const note=requiredReason(data.reason,500);
  if(typeof data.details!=='string'||data.details.length>5000)throw new HttpsError('invalid-argument','상세 내용을 5000자 이내로 입력해 주세요.');
  const details=data.details.trim();
  const ref=db().collection('reports').doc(`${uid}_${requestId}`);
  await db().runTransaction(async tx=>{
    await activeMember(tx,uid);
    const existing=await tx.get(ref);
    if(existing.exists)return;
    const video=data.targetType==='feed'?(await tx.get(db().doc(`feed_videos/${targetId}`))).data():null;
    const targetUid=data.targetType==='feed'?video?.userId:targetId;
    if(typeof targetUid!=='string'||targetUid===uid)throw new HttpsError('invalid-argument','본인 이외의 회원 또는 영상을 신고해 주세요.');
    const target=(await tx.get(db().doc(`users/${targetUid}`))).data();
    if(!target)throw new HttpsError('not-found','신고 대상을 찾을 수 없습니다.');
    const rateRef=db().doc(`community_rate_limits/${uid}`), rate=(await tx.get(rateRef)).data();
    if(rate?.lastReportAt?.toMillis()>Date.now()-10000)throw new HttpsError('resource-exhausted','신고를 접수했습니다. 잠시 후 다시 시도해 주세요.');
    tx.create(ref,{reporterUid:uid,reportedUid:targetUid,reportedUserName:target.name??'회원',targetType:data.targetType,targetId,reason:note,details,status:'pending',createdAt:stamp()});
    tx.set(rateRef,{lastReportAt:stamp()});
  });
  return {reportId:ref.id};
});
export const resolveReport=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['reportId','decision','reason']);
  const id=documentId(data.reportId,'reportId'), note=requiredReason(data.reason);
  if(!['dismiss','warn','hide'].includes(data.decision as string))throw new HttpsError('invalid-argument','처리 방법을 확인해 주세요.');
  const result=await db().runTransaction(async tx=>{
    if((await activeMember(tx,uid)).role!=='admin')throw new HttpsError('permission-denied','관리자만 처리할 수 있습니다.');
    const ref=db().doc(`reports/${id}`), report=(await tx.get(ref)).data();
    if(!report)throw new HttpsError('not-found','신고를 찾을 수 없습니다.');
    if(!['pending','PENDING'].includes(report.status))throw new HttpsError('failed-precondition','이미 처리한 신고입니다.');
    const targetUid=report.reportedUid??report.reportedUserId;
    const targetRef=db().doc(`users/${documentId(targetUid,'reportedUid')}`), target=(await tx.get(targetRef)).data();
    const videoRef=report.targetType==='feed'?db().doc(`feed_videos/${documentId(report.targetId,'targetId')}`):null;
    const video=videoRef?(await tx.get(videoRef)).data():null;
    if(data.decision==='hide'&&(!videoRef||video?.userId!==targetUid))throw new HttpsError('failed-precondition','영상 신고에서만 해당 영상을 숨길 수 있습니다.');
    if(data.decision==='warn'&&target)tx.update(targetRef,{warningCount:FieldValue.increment(1)});
    if(data.decision==='hide'){
      tx.update(videoRef!,{moderationStatus:'hidden',moderationReason:note,moderatedBy:uid,moderatedAt:stamp()});
      tx.delete(db().doc(`public_feed_videos/${videoRef!.id}`));
    }
    tx.update(ref,{status:'resolved',decision:data.decision,resolutionReason:note,resolvedBy:uid,resolvedAt:stamp()});
    tx.create(ref.collection('history').doc(),{actorUid:uid,decision:data.decision,reason:note,createdAt:stamp()});
    return {targetUid,reporterUid:report.reporterUid??report.reporterId};
  });
  void result;
  return {status:'resolved'};
});
export const notifyReportActivity=onDocumentWritten({...options,retry:true,document:'reports/{id}'},async e=>{
  if(e.data?.after.data()?.status!=='resolved'||e.data?.before.data()?.status==='resolved')return;
  const report=(await db().doc(`reports/${e.params.id}`).get()).data();
  if(report?.status!=='resolved')return;
  const reporter=report.reporterUid??report.reporterId,target=report.reportedUid??report.reportedUserId;
  await deliverNotification(reporter,`report:${e.params.id}:resolved`,{kind:'system',title:'신고 검토가 완료되었습니다',body:'접수한 신고를 운영진이 검토했습니다.',targetType:'profile',targetId:String(reporter)},new Date());
  if(report.decision==='warn')await deliverNotification(target,`report:${e.params.id}:warning`,{kind:'system',title:'운영 정책 안내',body:report.resolutionReason,targetType:'profile',targetId:String(target)},new Date());
});

export async function projectFeed(id: string) {
  await db().runTransaction(async (tx:Transaction)=>{
    const source=(await tx.get(db().doc(`feed_videos/${id}`))).data();
    const user=typeof source?.userId==='string'?(await tx.get(db().doc(`users/${source.userId}`))).data():null;
    const ref=db().doc(`public_feed_videos/${id}`);
    if(!source||source.deleting||source.moderationStatus==='hidden'||!user||user.profileCompleted!==true||(user.accountStatus??'active')!=='active'){tx.delete(ref);return;}
    const fields=['userId','title','description','storagePath','createdAt','likes'];
    tx.set(ref,{...Object.fromEntries(fields.filter(k=>source[k]!==undefined).map(k=>[k,source[k]])),userName:user.name??'회원',videoUrl:source.storagePath??source.videoUrl});
  });
}
export const projectPublicFeed=onDocumentWritten({...options,document:'feed_videos/{id}'},e=>projectFeed(e.params.id));
export const refreshAuthorFeed=onDocumentWritten({...options,document:'users/{uid}'},async e=>{
  const a=e.data?.after.data(),b=e.data?.before.data();
  if(['name','accountStatus','profileCompleted'].every(k=>a?.[k]===b?.[k]))return;
  const feeds=await db().collection('feed_videos').where('userId','==',e.params.uid).get();
  for(const doc of feeds.docs)await projectFeed(doc.id);
});
