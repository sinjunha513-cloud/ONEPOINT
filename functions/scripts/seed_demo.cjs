'use strict';
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||process.env.GCLOUD_PROJECT!=='demo-onepoint-payments')throw new Error('Demo emulators only.');
initializeApp({projectId:'demo-onepoint-payments'});
async function main(){
 const db=getFirestore(),auth=getAuth();
 for(const role of ['student','coach','admin']){
  try{await auth.createUser({uid:`demo-${role}`,email:`${role}@onepoint-demo.test`,password:'onepoint-demo-only',displayName:`체험 ${role}`});}catch(e){if(e.code!=='auth/uid-already-exists'&&e.code!=='auth/email-already-exists')throw e;}
  const accountRef=db.collection('users').doc(`demo-${role}`);
  if(!(await accountRef.get()).exists)await accountRef.set({uid:`demo-${role}`,email:`${role}@onepoint-demo.test`,name:role==='coach'?'원포인트 체험 코치':role==='student'?'체험 수강생':'체험 관리자',role,
   profileCompleted:true,termsAccepted:true,privacyAccepted:true,consentVersion:'2026-10-08-v1',consentedAt:Timestamp.now(),profileImage:'',targetTier:'비기너',lessonCount:0,reviewScores:[],teacherMatchCount:0,feedLikeCount:0,createdAt:Timestamp.now()},{merge:true});
 }
 await db.collection('instructors').doc('demo-coach').set({uid:'demo-coach',userId:'demo-coach',name:'원포인트 체험 코치',sport:'축구',career:'체험용 코칭 프로필',signatureMove:'감아차기',status:'approved',rating:'0.0',createdAt:Timestamp.now()});
 for(let i=1;i<=4;i++){
  const ref=db.collection('lesson_requests').doc(`demo-lesson-${i}`);
  if((await ref.get()).exists)continue;
  await ref.set({instructorId:'demo-coach',instructorUid:'demo-coach',instructorName:`원포인트 체험 코치 · 샘플 ${i}`,studentUid:'demo-student',studentName:'체험 수강생',participantIds:['demo-coach','demo-student'],sport:'축구',signatureMove:'감아차기',status:i===1?'pending':'accepted',
   ...(i===1?{}:{price:50000,currency:'KRW'}),isInstructorInitiated:false,createdAt:Timestamp.fromMillis(Date.now()-i*1000)});
 }
 console.log('Demo accounts and 4 lessons ready. No production data accessed.');
}
main().catch(e=>{console.error(e.code||e.message);process.exitCode=1;});
