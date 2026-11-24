import {getFirestore,FieldValue,Timestamp} from 'firebase-admin/firestore';
import {onCall} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {authenticatedInput,activeMember} from './platform_access';

const options={region:'asia-northeast3',maxInstances:2};
export async function rebuildActivity(uid:string,force=false){
  return getFirestore().runTransaction(async tx=>{
    const ref=getFirestore().doc(`users/${uid}`),user=(await tx.get(ref)).data();
    if(!user||user.profileCompleted!==true||(user.accountStatus??'active')!=='active')return;
    if(!force&&user.activityVersion===1)return;
    await tx.get(getFirestore().doc(`lesson_calendar_locks/${uid}`));
    const lessons=await tx.get(getFirestore().collection('lesson_requests').where('participantIds','array-contains',uid));
    const completed=lessons.docs.map(d=>d.data()).filter(d=>d.status==='completed'&&d.completedAt instanceof Timestamp&&d.completedAt.toMillis()<=Date.now()&&(!(d.scheduledEndAt instanceof Timestamp)||d.scheduledEndAt.toMillis()<=Date.now()));
    tx.update(ref,{completedLearningCount:completed.filter(d=>d.studentUid===uid).length,completedTeachingCount:completed.filter(d=>d.instructorUid===uid).length,activityVersion:1,activityUpdatedAt:FieldValue.serverTimestamp()});
  });
}
export const syncMyActivity=onCall({...options,timeoutSeconds:120},async r=>{
  const {uid}=authenticatedInput(r,[]);
  await getFirestore().runTransaction(tx=>activeMember(tx,uid));
  await rebuildActivity(uid);
  return {synced:true};
});
export const syncLessonActivity=onDocumentWritten({...options,document:'lesson_requests/{id}'},async e=>{
  const a=e.data?.after.data(),b=e.data?.before.data();
  if(a?.status===b?.status||![a?.status,b?.status].includes('completed'))return;
  const participants=new Set([a?.studentUid,a?.instructorUid,b?.studentUid,b?.instructorUid]);
  for(const uid of participants)if(typeof uid==='string')await rebuildActivity(uid,true);
});
