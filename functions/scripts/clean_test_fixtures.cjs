const {initializeApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
if(process.env.GCLOUD_PROJECT!=='demo-onepoint-payments'||!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST)throw new Error('Demo emulators only.');
initializeApp({projectId:'demo-onepoint-payments'});
async function main(){
 const db=getFirestore();
 const tests=await db.collection('payments').where('studentUid','==','test-student').get();
 for(const payment of tests.docs){
  const refunds=await payment.ref.collection('refunds').get();
  const batch=db.batch();for(const refund of refunds.docs)batch.delete(refund.ref);
  batch.delete(payment.ref);batch.delete(db.collection('payment_gateway_records').doc(payment.id));
  batch.delete(db.collection('refund_requests').doc(payment.id));batch.delete(db.collection('demo_gateway_payments').doc(`demo_${payment.id}`));
  batch.delete(db.collection('lesson_requests').doc(payment.data().lessonId));await batch.commit();
 }
 const lessons=await db.collection('lesson_requests').where('studentUid','==','test-student').get();
 for(const lesson of lessons.docs)await lesson.ref.delete();
 const totals={paidCount:0,grossApprovedAmount:0,refundCount:0,refundedAmount:0,completedLessonCount:0,completedAmount:0,platformFeeTotal:0,coachReadyTotal:0};
 const payments=await db.collection('payments').get();
 for(const payment of payments.docs){const p=payment.data();const lesson=(await db.collection('lesson_requests').doc(p.lessonId).get()).data();
  if(p.paidAt){totals.paidCount++;totals.grossApprovedAmount+=p.amount;}
  if(p.refundedAmount>0){totals.refundCount++;totals.refundedAmount+=p.refundedAmount;}
  if(lesson?.status==='completed'){totals.completedLessonCount++;totals.completedAmount+=p.amount-p.refundedAmount;totals.platformFeeTotal+=p.netPlatformFee??p.platformFee;totals.coachReadyTotal+=p.netCoachAmount??p.coachAmount;}
 }
 await db.collection('payment_stats').doc('summary').set({...totals,updatedAt:FieldValue.serverTimestamp()});
 console.log('Disposable test fixtures removed from isolated demo only. User-facing demo lessons retained.');
}
main().catch(e=>{console.error(e.code||e.message);process.exitCode=1;});
