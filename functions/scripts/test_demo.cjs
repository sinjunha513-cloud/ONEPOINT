'use strict';
const assert=require('node:assert/strict');
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
if(process.env.GCLOUD_PROJECT!=='demo-onepoint-payments'||!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Isolated demo emulators only.');
initializeApp({projectId:'demo-onepoint-payments'});
const db=getFirestore(),auth=getAuth(),tokens={},project='demo-onepoint-payments';
async function call(role,name,data){
 const response=await fetch(`http://127.0.0.1:5101/${project}/asia-northeast3/${name}`,{method:'POST',headers:{'Content-Type':'application/json',...(role?{Authorization:`Bearer ${tokens[role]}`}:{})},body:JSON.stringify({data})});
 const body=await response.json();if(body.error){const e=new Error(body.error.message);e.code=body.error.status;throw e;}return body.result;
}
async function rejected(task,code){await assert.rejects(task,e=>e.code===code);}
async function lesson(id,status='accepted'){
 await db.collection('lesson_requests').doc(id).set({studentUid:'test-student',studentName:'테스트 수강생',instructorUid:'test-coach',instructorId:'test-coach',instructorName:'테스트 코치',sport:'축구',signatureMove:'감아차기',participantIds:['test-student','test-coach'],status,price:50000,currency:'KRW',createdAt:Timestamp.now()});
}
async function main(){
 for(const role of ['student','coach','admin','other']){
  const uid=`test-${role}`;try{await auth.createUser({uid,email:`test-${role}@demo.test`,password:'demo-tests-only'});}catch(e){if(e.code!=='auth/uid-already-exists'&&e.code!=='auth/email-already-exists')throw e;}
  await db.collection('users').doc(uid).set({role:role==='other'?'student':role,profileCompleted:true,name:uid,lessonCount:0,reviewScores:[],teacherMatchCount:0,feedLikeCount:0});
  const login=await fetch('http://127.0.0.1:9198/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-only-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`test-${role}@demo.test`,password:'demo-tests-only',returnSecureToken:true})});
  tokens[role]=(await login.json()).idToken;assert.ok(tokens[role]);
 }
 await db.collection('instructors').doc('test-coach').set({uid:'test-coach',userId:'test-coach',name:'테스트 코치',status:'approved',sport:'축구',signatureMove:'감아차기'});
 const suffix=Date.now().toString(36),id=`test-complete-${suffix}`,refundLesson=`test-refund-${suffix}`;
 await lesson(id,'pending');
 await rejected(call(null,'preparePayment',{lessonId:id}),'UNAUTHENTICATED');
 await rejected(call('student','preparePayment',{lessonId:id}),'FAILED_PRECONDITION');console.log('PASS 1 unaccepted lesson cannot be paid');
 await call('coach','acceptPaidLesson',{lessonId:id,price:50000});console.log('PASS 2 approved coach fixes price on acceptance');
 await rejected(call('student','preparePayment',{lessonId:id,amount:100}),'INVALID_ARGUMENT');console.log('PASS 4 tampered amount rejected');
 const preparations=await Promise.all(Array.from({length:5},()=>call('student','preparePayment',{lessonId:id})));
 const payment=preparations[0],paymentId=payment.paymentId;assert.equal(new Set(preparations.map(p=>p.paymentId)).size,1);console.log('PASS 5 concurrent preparation is idempotent');
 await rejected(call('student','confirmPayment',{paymentId,paymentKey:'wrong-demo-key'}),'FAILED_PRECONDITION');
 assert.equal((await db.collection('lesson_requests').doc(id).get()).data().status,'accepted');console.log('PASS 6 failed approval leaves lesson unconfirmed');
 await call('student','confirmPayment',{paymentId,paymentKey:`demo_${paymentId}`});
 const paid=(await db.collection('payments').doc(paymentId).get()).data();assert.equal(paid.paymentStatus,'paid');assert.equal(paid.platformFee,6000);assert.equal(paid.coachAmount,44000);
 assert.equal((await db.collection('lesson_requests').doc(id).get()).data().status,'confirmed');console.log('PASS 3 50000 approved with 6000 fee and 44000 coach amount');
 const again=await call('student','confirmPayment',{paymentId,paymentKey:`demo_${paymentId}`});assert.equal(again.paymentStatus,'paid');
 await rejected(call('other','getPaymentStatus',{paymentId}),'PERMISSION_DENIED');console.log('PASS 9 unrelated payment access denied');
 const forbidden=await fetch(`http://127.0.0.1:8280/v1/projects/${project}/databases/(default)/documents/payments/${paymentId}?updateMask.fieldPaths=platformFee`,{method:'PATCH',headers:{'Content-Type':'application/json',Authorization:`Bearer ${tokens.student}`},body:JSON.stringify({fields:{platformFee:{integerValue:'1'}}})});assert.equal(forbidden.status,403);console.log('PASS 10 direct client fee mutation denied by actual Rules');
 await call('coach','completePaidLesson',{lessonId:id,reviewScore:4,reviewFeedback:'참여 확인',signatureMove:'감아차기',attendanceConfirmed:true});
 await call('coach','completePaidLesson',{lessonId:id,reviewScore:4,reviewFeedback:'재시도',signatureMove:'감아차기',attendanceConfirmed:true});
 const completed=(await db.collection('payments').doc(paymentId).get()).data();assert.equal(completed.payoutStatus,'ready');assert.notEqual(completed.payoutStatus,'completed');assert.equal((await db.collection('users').doc('test-student').get()).data().lessonCount,1);console.log('PASS 7 lesson completion makes payout ready exactly once');
 const coachView=await call('coach','getPaymentStatus',{paymentId});assert.equal(coachView.coachAmount,44000);assert.equal(coachView.studentUid,undefined);assert.equal(coachView.providerPaymentKey,undefined);console.log('PASS 12 coach receives only own settlement projection');
 const adminView=await call('admin','listPayments',{});assert.ok(adminView.payments.some(p=>p.paymentId===paymentId));await rejected(call('student','getPaymentSummary',{}),'PERMISSION_DENIED');const summary=await call('admin','getPaymentSummary',{});assert.ok(summary.platformFeeTotal>=6000);console.log('PASS 11 admin list and server aggregation accessible only to admin');
 await lesson(refundLesson);const refundPayment=await call('student','preparePayment',{lessonId:refundLesson});const rid=refundPayment.paymentId;
 await call('student','confirmPayment',{paymentId:rid,paymentKey:`demo_${rid}`});
 await call('student','requestPaymentRefund',{paymentId:rid,reason:'일정 변경'});assert.equal((await db.collection('payments').doc(rid).get()).data().payoutStatus,'held');
 await call('admin','cancelPayment',{paymentId:rid,refundId:`partial_${suffix}`,amount:5000,reason:'부분 환불 승인'});
 await call('admin','cancelPayment',{paymentId:rid,refundId:`partial_${suffix}`,amount:5000,reason:'동일 요청 재시도'});
 const partial=(await db.collection('payments').doc(rid).get()).data();assert.equal(partial.refundedAmount,5000);assert.equal(partial.paymentStatus,'partial_refunded');assert.equal(partial.netCoachAmount,39600);
 await call('coach','cancelPayment',{paymentId:rid,refundId:`full_${suffix}`,reason:'코치 일정 취소'});const full=(await db.collection('payments').doc(rid).get()).data();assert.equal(full.paymentStatus,'refunded');assert.equal(full.refundedAmount,50000);assert.equal(full.payoutStatus,'cancelled');assert.equal((await db.collection('lesson_requests').doc(refundLesson).get()).data().status,'cancelled');console.log('PASS 8 partial/full refund verified, net fees adjusted and duplicate refund prevented');
 const mismatch=`test-mismatch-${suffix}`;await lesson(mismatch);const mp=await call('student','preparePayment',{lessonId:mismatch});
 await db.collection('demo_gateway_payments').doc(`demo_${mp.paymentId}`).set({paymentKey:`demo_${mp.paymentId}`,providerOrderId:mp.providerOrderId,amount:100,balanceAmount:100,currency:'KRW',status:'DONE',paymentMethod:'체험'});
 await rejected(call('student','confirmPayment',{paymentId:mp.paymentId,paymentKey:`demo_${mp.paymentId}`}), 'DATA_LOSS');
 assert.equal((await db.collection('payments').doc(mp.paymentId).get()).data().paymentStatus,'pending');console.log('PASS mismatched PG amount cannot become paid');
 const recoveryId=`test-recovery-${suffix}`;await lesson(recoveryId);const rp=await call('student','preparePayment',{lessonId:recoveryId});
 const {PaymentLifecycle}=require('../lib/src/payment_lifecycle');let failCommit=false;
 const originalTransaction=db.runTransaction.bind(db);db.runTransaction=async(...args)=>{if(failCommit){failCommit=false;throw new Error('injected commit outage');}return originalTransaction(...args);};
 const verified={paymentKey:'recovery-key',providerOrderId:rp.providerOrderId,amount:50000,balanceAmount:50000,currency:'KRW',status:'DONE',paymentMethod:'체험'};
 const lifecycle=new PaymentLifecycle(db,{confirm:async()=>{failCommit=true;return verified;},get:async()=>verified,cancel:async()=>{throw new Error('unused');}});
 await assert.rejects(lifecycle.confirm('test-student',rp.paymentId,'recovery-key'),/injected commit outage/);
 assert.equal((await db.collection('payments').doc(rp.paymentId).get()).data().paymentStatus,'pending');
 const recovered=await lifecycle.reconcile('test-student',rp.paymentId);assert.equal(recovered.paymentStatus,'paid');
 assert.equal((await db.collection('lesson_requests').doc(recoveryId).get()).data().status,'confirmed');db.runTransaction=originalTransaction;
 console.log('PASS approved PG result survives DB outage and reconciles without duplicate approval');
 const external=(await db.collection('demo_gateway_payments').doc(`demo_${paymentId}`).get()).data();
 await db.collection('demo_gateway_payments').doc(`demo_${paymentId}`).set({...external,balanceAmount:0,status:'CANCELED'});
 await call('admin','reconcilePayment',{paymentId});
 const attended=(await db.collection('lesson_requests').doc(id).get()).data();
 assert.equal(attended.status,'completed');assert.equal(attended.attendanceBadge.signatureMove,'감아차기');
 assert.equal((await db.collection('payments').doc(paymentId).get()).data().paymentStatus,'refunded');
 console.log('PASS external refund preserves genuine completed attendance and badge');
 console.log('All 12 requested scenarios plus financial recovery checks passed on demo server/PG simulator. No real Toss payment or production data.');
}
main().catch(e=>{console.error('FAIL',e.code||'',e.message);process.exitCode=1;});
