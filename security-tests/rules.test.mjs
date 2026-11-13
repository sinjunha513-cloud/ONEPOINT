import {after, before, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, setLogLevel} from 'firebase/firestore';
import {ref, uploadBytes, getBytes, deleteObject, updateMetadata} from 'firebase/storage';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';

setLogLevel('silent');
const projectId = 'demo-onepoint-security';
// Never permit these tests to fall back to a production endpoint.
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Run through npm test: both emulators are required.');
process.env.GCLOUD_PROJECT = projectId;
let env;
const ctx = uid => uid ? env.authenticatedContext(uid, {email: `${uid}@example.test`}) : env.unauthenticatedContext();
const db = uid => ctx(uid).firestore();
const store = uid => ctx(uid).storage(`${projectId}.appspot.com`);
const profile = (uid, extra = {}) => ({uid, email: `${uid}@example.test`, name: uid, role: 'student', requestedRole: 'student', profileCompleted: true,
  termsAccepted: true, privacyAccepted: true, consentVersion: '2026-10-08-v1', lessonCount: 0, reviewScores: [], teacherMatchCount: 0, feedLikeCount: 0, ...extra});
async function seed(path, data) { await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), path), data)); }
const lesson = {studentUid: 'student', instructorUid: 'coach', participantIds: ['coach','student'], studentName: 'student', instructorName: 'coach', sport: '축구', status: 'accepted', paymentRequired: false};
before(async () => {
  const origin=JSON.parse(readFileSync('../docs/rules-origin.json','utf8'));
  for(const [name,record] of Object.entries(origin)) assert.equal(createHash('sha256').update(readFileSync(`../${name}`)).digest('hex'),record.sha256,`Original rules changed: ${name}`);
  env = await initializeTestEnvironment({projectId, firestore: {host: '127.0.0.1', port: 8080, rules: readFileSync('../firestore.rules', 'utf8')}, storage: {host: '127.0.0.1', port: 9199, rules: readFileSync('../storage.rules', 'utf8')}});
});
beforeEach(async () => {
  await env.clearFirestore(); await env.clearStorage();
  for (const [uid, extra] of Object.entries({student: {}, coach: {role:'coach'}, other: {}, admin: {role:'admin'}, suspended: {accountStatus:'suspended'}, suspendedAdmin: {role:'admin', accountStatus:'suspended'}, incomplete: {profileCompleted:false, requestedRole:'coach', consentedAt:new Date(0)}})) await seed(`users/${uid}`, profile(uid, extra));
  await seed('instructors/coach', {uid:'coach',userId:'coach',name:'coach',sport:'축구',status:'approved',career:'experience',rating:'0.0',signatureMove:'kick'});
  await seed('lesson_requests/lesson', lesson);
  await seed('chat_rooms/coach_student', {participantIds:['coach','student'],studentUid:'student',coachUid:'coach',studentName:'student',coachName:'coach'});
});
after(async () => { await env?.cleanup(); });

test('users: self/admin only; no other email/list access, including unsigned and missing member', async () => {
  await assertSucceeds(getDoc(doc(db('student'), 'users/student')));
  await assertSucceeds(getDoc(doc(db('admin'), 'users/student')));
  await assertSucceeds(getDocs(collection(db('admin'), 'users')));
  for (const uid of ['student','coach','other','missing','incomplete','suspended','suspendedAdmin',null]) {
    const target = uid === 'student' ? 'coach' : 'student';
    await assertFails(getDoc(doc(db(uid), `users/${target}`)));
    await assertFails(getDocs(collection(db(uid), 'users')));
  }
  // Suspension gate still permits observing one's own accountStatus for logout UI.
  await assertSucceeds(getDoc(doc(db('suspended'), 'users/suspended')));
});
test('signup: initialize, consent completion and profile edits; role/status/counters stay protected', async () => {
  const d = db('new'); const r = doc(d,'users/new');
  await assertSucceeds(getDoc(r));
  const initial = profile('new',{profileCompleted:false,createdAt:serverTimestamp()});
  delete initial.termsAccepted; delete initial.privacyAccepted; delete initial.consentVersion;
  await assertSucceeds(setDoc(r,initial));
  await assertFails(updateDoc(r,{profileCompleted:true,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(r,{profileCompleted:true,termsAccepted:true,privacyAccepted:true,consentVersion:'2026-10-08-v1',consentedAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(r,{name:'new name',updatedAt:serverTimestamp()}));
  for (const fields of [{role:'admin'},{role:'coach'},{accountStatus:'active'},{lessonCount:99},{feedLikeCount:99},{email:'forged@example.test'},{profileCompleted:false}]) await assertFails(updateDoc(r,{...fields,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('suspended'),'users/suspended'),{name:'changed',updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db('forged'),'users/forged'),{...initial,uid:'forged',email:'forged@example.test',role:'admin'}));
  await assertSucceeds(updateDoc(doc(db('admin'),'users/student'),{role:'coach',updatedAt:serverTimestamp()}));
});
test('public data is readable only by completed active members and never client-writable', async () => {
  await seed('public_users/coach',{uid:'coach',name:'coach'});
  await seed('public_instructors/coach',{uid:'coach',name:'coach',sport:'축구',status:'approved'});
  for (const uid of ['student','coach','admin']) {
    await assertSucceeds(getDoc(doc(db(uid),'public_users/coach')));
    await assertSucceeds(getDocs(query(collection(db(uid),'public_instructors'),where('sport','==','축구'),where('status','==','approved'))));
    await assertFails(setDoc(doc(db(uid),'public_users/coach'),{email:'leak'}));
  }
  for (const uid of ['missing','incomplete','suspended',null]) await assertFails(getDoc(doc(db(uid),'public_users/coach')));
  await assertFails(getDoc(doc(db('student'),'instructors/coach')));
});
test('coach applicant can create private pending application and finish signup without self approval', async () => {
  await seed('signature_badges/kick',{name:'kick',colorIndex:7});
  const d = db('incomplete'); const r = doc(d,'instructors/incomplete');
  const data = {uid:'incomplete',userId:'incomplete',name:'applicant',sport:'축구',career:'career',signatureMove:'kick',signatureBadgeId:'kick',signatureBadgeColorIndex:7,status:'pending',rating:'0.0',createdAt:serverTimestamp(),submittedAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(setDoc(r,{...data,status:'approved'}));
  const batch = writeBatch(d); batch.set(r,data); batch.update(doc(d,'users/incomplete'),{profileCompleted:true,updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(r,{status:'approved'}));
  await assertFails(updateDoc(r,{rating:'5.0'}));
  await assertSucceeds(getDoc(r));
  await assertFails(getDoc(doc(db('other'),'instructors/incomplete')));
  const adminDb=db('admin'), approval=writeBatch(adminDb);
  approval.update(doc(adminDb,'instructors/incomplete'),{status:'approved',reviewedBy:'admin',reviewedAt:serverTimestamp(),approvedAt:serverTimestamp(),updatedAt:serverTimestamp()});
  approval.update(doc(adminDb,'users/incomplete'),{role:'coach',updatedAt:serverTimestamp()});
  await assertSucceeds(approval.commit());
});
test('lesson access and state transitions preserve participant/payment fields', async () => {
  for (const uid of ['student','coach','admin']) await assertSucceeds(getDoc(doc(db(uid),'lesson_requests/lesson')));
  for (const uid of ['other','missing','incomplete','suspended',null]) await assertFails(getDoc(doc(db(uid),'lesson_requests/lesson')));
  await seed('lesson_requests/pending',{...lesson,status:'pending'});
  await assertFails(updateDoc(doc(db('student'),'lesson_requests/pending'),{status:'accepted',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/pending'),{participantIds:['coach','other'],status:'accepted',updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(db('coach'),'lesson_requests/pending'),{status:'accepted',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/lesson'),{status:'completed',updatedAt:serverTimestamp()}));
  await seed('lesson_requests/paid',{...lesson,status:'pending',paymentRequired:true});
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/paid'),{status:'accepted',updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db('student'),'lesson_requests/forged'),lesson));
});
test('chat: atomic new message + summary allowed; standalone, replay, spoof and participant edits denied', async () => {
  const d=db('student'), room=doc(d,'chat_rooms/coach_student');
  const msg=doc(d,'chat_rooms/coach_student/messages/msg');
  const batch=writeBatch(d); batch.set(msg,{senderId:'student',text:'hello',createdAt:serverTimestamp()}); batch.update(room,{lastMessage:'hello',lastMessageId:'msg',updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDocs(collection(db('coach'),'chat_rooms/coach_student/messages')));
  await assertSucceeds(getDocs(query(collection(d,'chat_rooms'),where('participantIds','array-contains','student'))));
  await assertFails(updateDoc(room,{lastMessage:'forged',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(room,{lastMessage:'hello',lastMessageId:'msg',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(room,{participantIds:['student','other']}));
  await assertFails(updateDoc(msg,{text:'edited'}));
  const spoof=writeBatch(d); spoof.set(doc(d,'chat_rooms/coach_student/messages/spoof'),{senderId:'coach',text:'spoof',createdAt:serverTimestamp()}); spoof.update(room,{lastMessage:'spoof',lastMessageId:'spoof',updatedAt:serverTimestamp()}); await assertFails(spoof.commit());
  for(const uid of ['other','admin','incomplete','missing','suspended',null]) await assertFails(getDoc(doc(db(uid),'chat_rooms/coach_student')));
});
test('reports bind reporter uid/email to auth; private from other members', async () => {
  const r=doc(db('student'),'reports/report');
  const data={reporterId:'student',reporterEmail:'student@example.test',reportedUserId:'coach',reportedUserName:'coach',reason:'reason',detail:'details',sanctionType:'OTHER',status:'PENDING',createdAt:serverTimestamp()};
  await assertFails(setDoc(r,{...data,reporterEmail:'coach@example.test'}));
  await assertFails(setDoc(r,{...data,reporterId:'coach'}));
  await assertSucceeds(setDoc(r,data));
  await assertFails(getDoc(r)); await assertSucceeds(getDoc(doc(db('admin'),'reports/report')));
});
const feed = {userId:'student',userName:'student',title:'title',description:'',storagePath:'videos/student/clip.mp4',videoUrl:'videos/student/clip.mp4',likes:0,createdAt:serverTimestamp()};
test('feed metadata binds author/name/path and immutable counters/URLs', async () => {
  const r=doc(db('student'),'feed_videos/video');
  for (const fields of [{userId:'coach'},{userName:'coach'},{storagePath:'videos/coach/clip.mp4'},{videoUrl:'https://evil.test/video.mp4'},{likes:100},{createdAt:new Date(0)}]) await assertFails(setDoc(r,{...feed,...fields}));
  await assertSucceeds(setDoc(r,feed));
  for(const uid of ['student','coach','admin']) await assertFails(updateDoc(doc(db(uid),'feed_videos/video'),{likes:99}));
  await assertFails(deleteDoc(r));
});
test('all payment and internal collections reject client read/write, including admin', async () => {
  for(const collectionName of ['payments','payment_gateway_records','payment_stats','refunds','refund_requests','demo_gateway_payments','demo_gateway_operations','unknown']) {
    await seed(`${collectionName}/test`,{value:1});
    for(const uid of ['student','coach','admin','missing','suspended',null]) {
      const r=doc(db(uid),`${collectionName}/test`);
      await assertFails(getDoc(r)); await assertFails(setDoc(r,{value:2})); await assertFails(deleteDoc(r));
    }
  }
});
const bytes = new Uint8Array([1,2,3]);
test('Storage shortform: owner create/delete; no overwrite/metadata edits; membership and MIME/size gates', async () => {
  const own=ref(store('student'),'videos/student/clip.mp4');
  await assertSucceeds(uploadBytes(own,bytes,{contentType:'video/mp4'}));
  await assertFails(uploadBytes(own,bytes,{contentType:'video/mp4'}));
  await assertFails(updateMetadata(own,{customMetadata:{forged:'true'}}));
  await assertSucceeds(getBytes(ref(store('coach'),'videos/student/clip.mp4')));
  await assertFails(deleteObject(ref(store('coach'),'videos/student/clip.mp4')));
  await assertFails(deleteObject(ref(store('admin'),'videos/student/clip.mp4')));
  await assertFails(uploadBytes(ref(store('student'),'videos/coach/forged.mp4'),bytes,{contentType:'video/mp4'}));
  await assertFails(uploadBytes(ref(store('student'),'videos/student/wrong.mp4'),bytes,{contentType:'text/plain'}));
  await assertFails(uploadBytes(ref(store('student'),'videos/student/empty.mp4'),new Uint8Array(),{contentType:'video/mp4'}));
  await assertFails(uploadBytes(ref(store('student'),'videos/student/large.mp4'),new Uint8Array(100*1024*1024+1),{contentType:'video/mp4'}));
  for(const uid of ['incomplete','missing','suspended',null]) {
    await assertFails(getBytes(ref(store(uid),'videos/student/clip.mp4')));
    await assertFails(uploadBytes(ref(store(uid),`videos/${uid ?? 'anonymous'}/own.mp4`),bytes,{contentType:'video/mp4'}));
  }
  await assertSucceeds(deleteObject(own));
});
test('Storage PDF: incomplete applicant and admin read; all other users denied; no overwrite', async () => {
  const path='coach_documents/incomplete/pdf_test.pdf'; const own=ref(store('incomplete'),path);
  await assertSucceeds(uploadBytes(own,bytes,{contentType:'application/pdf'}));
  await assertSucceeds(getBytes(own)); await assertSucceeds(getBytes(ref(store('admin'),path)));
  for(const uid of ['student','coach','other','missing','suspended','suspendedAdmin',null]) await assertFails(getBytes(ref(store(uid),path)));
  await assertFails(uploadBytes(own,bytes,{contentType:'application/pdf'}));
  await assertFails(deleteObject(own));
  await assertFails(uploadBytes(ref(store('incomplete'),'coach_documents/incomplete/pdf_bad.pdf'),bytes,{contentType:'video/mp4'}));
  await assertFails(uploadBytes(ref(store('incomplete'),'coach_documents/incomplete/pdf_large.pdf'),new Uint8Array(5*1024*1024+1),{contentType:'application/pdf'}));
});
test('Storage feedback: actual lesson identities, status, metadata and ownership enforced', async () => {
  const path='lesson_feedback/lesson/student/clip.mp4'; const own=ref(store('student'),path);
  const meta={contentType:'video/mp4',customMetadata:{lessonId:'lesson',uploaderUid:'student'}};
  await assertFails(uploadBytes(own,bytes,{contentType:'video/mp4',customMetadata:{lessonId:'forged',uploaderUid:'coach'}}));
  await assertSucceeds(uploadBytes(own,bytes,meta));
  await assertSucceeds(uploadBytes(ref(store('student'),'lesson_feedback/lesson/student/legacy.webm'),bytes,{contentType:'video/webm'}));
  await assertSucceeds(getBytes(ref(store('coach'),path)));
  await assertFails(uploadBytes(own,bytes,meta));
  for(const uid of ['other','missing','incomplete','suspended',null]) await assertFails(getBytes(ref(store(uid),path)));
  await assertSucceeds(getBytes(ref(store('admin'),path)));
  await assertFails(deleteObject(ref(store('coach'),path)));
  await seed('lesson_requests/forged',{...lesson,participantIds:['other','student']});
  await assertFails(uploadBytes(ref(store('other'),'lesson_feedback/forged/other/clip.mp4'),bytes,{contentType:'video/mp4',customMetadata:{lessonId:'forged',uploaderUid:'other'}}));
  for(const status of ['pending','cancelled','rejected']) {
    await seed(`lesson_requests/${status}`,{...lesson,status});
    await assertFails(uploadBytes(ref(store('student'),`lesson_feedback/${status}/student/clip.mp4`),bytes,{contentType:'video/mp4',customMetadata:{lessonId:status,uploaderUid:'student'}}));
  }
  await assertSucceeds(deleteObject(own));
});
test('feedback Firestore metadata requires participant, author, path and eligible status', async () => {
  const r=doc(db('student'),'lesson_requests/lesson/feedback_videos/video');
  const data={uploaderUid:'student',uploaderName:'student',lessonId:'lesson',storagePath:'lesson_feedback/lesson/student/clip.mp4',description:'',createdAt:serverTimestamp()};
  for(const change of [{uploaderUid:'coach'},{uploaderName:'coach'},{lessonId:'other'},{storagePath:'lesson_feedback/lesson/coach/clip.mp4'}]) await assertFails(setDoc(r,{...data,...change}));
  await assertSucceeds(setDoc(r,data));
  await assertSucceeds(getDoc(doc(db('coach'),'lesson_requests/lesson/feedback_videos/video')));
  await assertFails(getDoc(doc(db('other'),'lesson_requests/lesson/feedback_videos/video')));
});

const require = createRequire(import.meta.url);
let api;
const request = (uid,data) => ({auth:uid ? {uid,token:{email:`${uid}@example.test`}} : undefined,data});
const call = (name,uid,data) => { api ??= require('../functions/lib/src/index.js'); return api[name].run(request(uid,data)); };
test('server workflows: booking, acceptance/chat creation, completion, idempotent likes and public projection', async () => {
  const {lessonId}=await call('requestLesson','student',{instructorId:'coach'});
  await assert.rejects(call('requestLesson','student',{instructorId:'coach'}),{code:'already-exists'});
  const d=db('coach'), batch=writeBatch(d);
  batch.update(doc(d,`lesson_requests/${lessonId}`),{status:'accepted',updatedAt:serverTimestamp()});
  // Original active-pair + acceptedRoom linkage is required in this same batch.
  await env.withSecurityRulesDisabled(c => deleteDoc(doc(c.firestore(),'chat_rooms/coach_student')));
  batch.set(doc(d,'chat_rooms/coach_student'),{participantIds:['coach','student'],studentUid:'student',studentName:'student',coachUid:'coach',coachName:'coach'});
  await assertSucceeds(batch.commit());
  await assert.rejects(call('completeLesson','other',{lessonId,reviewScore:4,feedback:''}),{code:'permission-denied'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:'good'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:'good'});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
  await assertSucceeds(setDoc(doc(db('student'),'feed_videos/video'),feed));
  await call('setFeedLiked','other',{videoId:'video',liked:true});
  await call('setFeedLiked','other',{videoId:'video',liked:true});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().feedLikeCount,1);
  await call('setFeedLiked','other',{videoId:'video',liked:false});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().feedLikeCount,0);
  const {projectPublicProfile}=require('../functions/lib/src/security_workflows.js');
  await projectPublicProfile('coach');
  const publicUser=(await getDoc(doc(db('student'),'public_users/coach'))).data();
  assert.equal(publicUser.email,undefined); assert.equal(publicUser.accountStatus,undefined);
  const publicCoach=(await getDoc(doc(db('student'),'public_instructors/coach'))).data();
  assert.equal(publicCoach.careerPdfId,undefined); assert.equal(publicCoach.status,'approved');
});
test('server boundaries reject missing/incomplete/suspended accounts and forged amount payloads', async () => {
  for(const uid of [null,'missing','incomplete','suspended','suspendedAdmin']) {
    await assert.rejects(call('requestLesson',uid,{instructorId:'coach'}),{code:uid ? 'permission-denied':'unauthenticated'});
    await assert.rejects(call('setFeedLiked',uid,{videoId:'video',liked:true}),{code:uid ? 'permission-denied':'unauthenticated'});
  }
  await assert.rejects(call('requestLesson','student',{instructorId:'coach',paymentRequired:false,price:1}),{code:'invalid-argument'});
});
test('server scheduling: owner-only slots, overlap/booking lock, reschedule and history', async () => {
  const start=Date.now()+86400000, end=start+3600000;
  await assert.rejects(call('saveAvailabilitySlot','student',{startAtMillis:start,endAtMillis:end}),{code:'permission-denied'});
  const {slotId}=await call('saveAvailabilitySlot','coach',{startAtMillis:start,endAtMillis:end});
  await assert.rejects(call('saveAvailabilitySlot','coach',{startAtMillis:start,endAtMillis:end}),{code:'already-exists'});
  const {lessonId}=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId});
  await assert.rejects(call('deleteAvailabilitySlot','coach',{slotId}),{code:'failed-precondition'});
  const next=await call('saveAvailabilitySlot','coach',{startAtMillis:end,endAtMillis:end+3600000});
  await assert.rejects(call('rescheduleLesson','other',{lessonId,slotId:next.slotId}),{code:'permission-denied'});
  await call('rescheduleLesson','coach',{lessonId,slotId:next.slotId});
  const history=await getDocs(collection(db('student'),`lesson_requests/${lessonId}/schedule_changes`));
  assert.equal(history.size,1); assert.ok(history.docs[0].data().newStartAt);
  const third=await call('saveAvailabilitySlot','coach',{startAtMillis:end+3600000,endAtMillis:end+7200000});
  await call('rescheduleLesson','student',{lessonId,slotId:third.slotId});
  assert.equal((await getDoc(doc(db('student'),`lesson_requests/${lessonId}`))).data().scheduleRevision,2);
});

test('coach PDF validation verifies actual bytes server-side and cannot be forged by clients', async () => {
  const {PDFDocument}=require('../functions/node_modules/pdf-lib');
  const pdf=await PDFDocument.create(); pdf.addPage(); const valid=await pdf.save();
  await assertSucceeds(uploadBytes(ref(store('incomplete'),'coach_documents/incomplete/pdf_valid.pdf'),valid,{contentType:'application/pdf'}));
  await call('validateCareerPdf','incomplete',{fileId:'pdf_valid',fileName:'career.pdf'});
  const record=doc(db('incomplete'),'coach_document_uploads/incomplete/files/pdf_valid');
  assert.equal((await getDoc(record)).data().verified,true);
  await assertFails(setDoc(record,{verified:true}));
  await assertFails(getDoc(doc(db('other'),'coach_document_uploads/incomplete/files/pdf_valid')));
  await seed('signature_badges/kick',{name:'kick',colorIndex:7});
  const d=db('incomplete');
  const application={uid:'incomplete',userId:'incomplete',name:'applicant',sport:'축구',career:'',careerPdfId:'pdf_valid',signatureMove:'kick',signatureBadgeId:'kick',signatureBadgeColorIndex:7,status:'pending',rating:'0.0',createdAt:serverTimestamp(),submittedAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(setDoc(doc(d,'instructors/incomplete'),{...application,careerPdfId:'unverified'}));
  const batch=writeBatch(d); batch.set(doc(d,'instructors/incomplete'),application); batch.update(doc(d,'users/incomplete'),{profileCompleted:true,updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  const adminDb=db('admin');
  const approval=writeBatch(adminDb); approval.update(doc(adminDb,'instructors/incomplete'),{status:'approved',reviewedBy:'admin',reviewedAt:serverTimestamp(),approvedAt:serverTimestamp(),updatedAt:serverTimestamp()}); approval.update(doc(adminDb,'users/incomplete'),{role:'coach',updatedAt:serverTimestamp()});
  await assertSucceeds(approval.commit());
  const {lessonId}=await call('requestLesson','student',{instructorId:'incomplete'});
  assert.ok(lessonId);
  await assertSucceeds(uploadBytes(ref(store('incomplete'),'coach_documents/incomplete/pdf_bad.pdf'),bytes,{contentType:'application/pdf'}));
  await assert.rejects(call('validateCareerPdf','incomplete',{fileId:'pdf_bad',fileName:'career.pdf'}));
  await assert.rejects(call('validateCareerPdf','suspended',{fileId:'pdf_valid',fileName:'career.pdf'}),{code:'permission-denied'});
});
test('server deletion: owner-only, correct storage path, retry and like EXP consistency', async () => {
  await assertSucceeds(uploadBytes(ref(store('student'),'videos/student/clip.mp4'),bytes,{contentType:'video/mp4'}));
  await assertSucceeds(setDoc(doc(db('student'),'feed_videos/video'),feed));
  await call('setFeedLiked','other',{videoId:'video',liked:true});
  await assert.rejects(call('deleteVideo','other',{kind:'feed',videoId:'video'}),{code:'permission-denied'});
  await assert.rejects(call('deleteVideo','admin',{kind:'feed',videoId:'video'}),{code:'permission-denied'});
  await call('deleteVideo','student',{kind:'feed',videoId:'video'});
  assert.equal((await getDoc(doc(db('student'),'feed_videos/video'))).exists(),false);
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().feedLikeCount,0);
  await assert.rejects(getBytes(ref(store('student'),'videos/student/clip.mp4')),{code:'storage/object-not-found'});
  await assert.rejects(call('deleteVideo','student',{kind:'feed',videoId:'video'}),{code:'not-found'});
  await assertSucceeds(uploadBytes(ref(store('student'),'lesson_feedback/lesson/student/clip.mp4'),bytes,{contentType:'video/mp4',customMetadata:{lessonId:'lesson',uploaderUid:'student'}}));
  await seed('lesson_requests/lesson/feedback_videos/video',{uploaderUid:'student',storagePath:'lesson_feedback/lesson/student/clip.mp4'});
  await assert.rejects(call('deleteVideo','coach',{kind:'feedback',lessonId:'lesson',videoId:'video'}),{code:'permission-denied'});
  await call('deleteVideo','student',{kind:'feedback',lessonId:'lesson',videoId:'video'});
});
test('public projections remove revoked accounts and redact private slot details', async () => {
  api ??= require('../functions/lib/src/index.js');
  const {projectPublicProfile}=require('../functions/lib/src/security_workflows.js');
  const {projectSlot}=require('../functions/lib/src/scheduling.js');
  await projectPublicProfile('coach');
  await seed('instructors/coach/availability/slot',{coachUid:'coach',startAt:new Date(),endAt:new Date(Date.now()+3600000),status:'booked',lessonId:'private-lesson',studentUid:'private-student'});
  await projectSlot('coach','slot');
  await assertFails(getDoc(doc(db('student'),'instructors/coach/availability/slot')));
  const slot=(await getDoc(doc(db('student'),'instructors/coach/public_availability/slot'))).data();
  assert.equal(slot.lessonId,undefined); assert.equal(slot.studentUid,undefined);
  await seed('users/coach',profile('coach',{role:'coach',accountStatus:'suspended'}));
  await projectPublicProfile('coach');
  assert.equal((await getDoc(doc(db('student'),'public_instructors/coach'))).exists(),false);
  assert.equal((await getDoc(doc(db('student'),'public_users/coach'))).exists(),false);
});
test('catalog signup transaction works and forged badge selections/counters fail', async () => {
  const d=db('incomplete'), batch=writeBatch(d);
  batch.set(doc(d,'signature_badges/kick'),{name:'kick',normalizedName:'kick',sequence:0,colorIndex:7,createdBy:'incomplete',createdAt:serverTimestamp()});
  batch.set(doc(d,'signature_badge_meta/catalog'),{nextSequence:1,lastBadgeId:'kick',updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(d,'signature_badge_meta/catalog'),{nextSequence:99}));
  await assertFails(updateDoc(doc(db('student'),'users/student'),{signatureMove:'forged',signatureBadgeId:'kick',signatureBadgeColorIndex:7,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('coach'),'users/coach'),{signatureMove:'forged',signatureBadgeId:'kick',signatureBadgeColorIndex:7,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(db('coach'),'users/coach'),{signatureMove:'kick',signatureBadgeId:'kick',signatureBadgeColorIndex:7,updatedAt:serverTimestamp()}));
});
test('booking concurrency, invalid completion and legacy signature fallback preserve invariants', async () => {
  const results=await Promise.allSettled([call('requestLesson','student',{instructorId:'coach'}),call('requestLesson','student',{instructorId:'coach'})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const lessonId=results.find(r=>r.status==='fulfilled').value.lessonId;
  for(const score of [0,5.01,NaN,Infinity]) await assert.rejects(call('completeLesson','coach',{lessonId,reviewScore:score,feedback:''}),{code:'invalid-argument'});
  await assert.rejects(call('completeLesson','coach',{lessonId,reviewScore:4,feedback:''}),{code:'failed-precondition'});
  await assertSucceeds(updateDoc(doc(db('coach'),`lesson_requests/${lessonId}`),{status:'accepted',updatedAt:serverTimestamp()}));
  await env.withSecurityRulesDisabled(c => deleteDoc(doc(c.firestore(),'instructors/coach')));
  await assert.rejects(call('completeLesson','coach',{lessonId,reviewScore:4,feedback:''}),{code:'permission-denied'});
  await seed('instructors/coach',{uid:'coach',userId:'coach',name:'coach',sport:lesson.sport,status:'approved'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:''});
  const completed=(await getDoc(doc(db('student'),`lesson_requests/${lessonId}`))).data();
  assert.equal(completed.attendanceBadge.signatureMove,'kick');
  const second='second'; await seed(`lesson_requests/${second}`,{studentUid:'student',instructorUid:'coach',participantIds:['coach','student'],status:'accepted',signatureMove:'kick',paymentRequired:false});
  await call('completeLesson','coach',{lessonId:second,reviewScore:4,feedback:''});
  const student=(await getDoc(doc(db('student'),'users/student'))).data();
  assert.equal(student.lessonCount,2); assert.deepEqual(student.reviewScores,[4,4]);
});

test('original client booking/pair/accepted-room transaction remains supported and rejects partial writes', async () => {
  const d=db('student'), r=doc(d,'lesson_requests/client'), pair=doc(d,'active_lesson_requests/coach_student');
  const data={...lesson,instructorId:'coach',status:'pending',signatureMove:'kick',isInstructorInitiated:false,createdAt:serverTimestamp()};
  await assertFails(setDoc(r,data));
  for(const patch of [{studentName:'forged'},{instructorName:'forged'},{signatureMove:'forged'},{participantIds:['student','other']}]) {
    const batch=writeBatch(d); batch.set(r,{...data,...patch}); batch.set(pair,{requestId:'client',participantIds:['coach','student']});
    await assertFails(batch.commit());
  }
  const create=writeBatch(d); create.set(r,data); create.set(pair,{requestId:'client',participantIds:['coach','student']});
  await assertSucceeds(create.commit());
  await env.withSecurityRulesDisabled(c=>deleteDoc(doc(c.firestore(),'chat_rooms/coach_student')));
  const coachDb=db('coach'), coachRef=doc(coachDb,'lesson_requests/client');
  await assertFails(updateDoc(coachRef,{status:'accepted',updatedAt:serverTimestamp()}));
  const accept=writeBatch(coachDb); accept.update(coachRef,{status:'accepted',updatedAt:serverTimestamp()});
  accept.set(doc(coachDb,'chat_rooms/coach_student'),{participantIds:['coach','student'],studentUid:'student',studentName:'student',coachUid:'coach',coachName:'coach'});
  await assertSucceeds(accept.commit());
  await assertFails(updateDoc(coachRef,{status:'rejected',updatedAt:serverTimestamp()}));
});

test('original completion/studentProgress/closedPair validation remains atomic and immutable', async () => {
  await seed('active_lesson_requests/coach_student',{requestId:'lesson',participantIds:['coach','student']});
  const d=db('coach'), r=doc(d,'lesson_requests/lesson'), student=doc(d,'users/student');
  const completion={status:'completed',reviewScore:4,reviewFeedback:'good',attendanceBadge:{instructorUid:'coach',instructorName:'coach',sport:lesson.sport,signatureMove:'kick',awardedAt:serverTimestamp(),verifiedBy:'coach'},completedAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(updateDoc(r,completion));
  await assertFails(updateDoc(student,{lastCompletedLessonId:'lesson',lessonCount:1,reviewScores:[4],teacherMatchCount:0}));
  const batch=writeBatch(d); batch.update(r,completion); batch.update(student,{lastCompletedLessonId:'lesson',lessonCount:1,reviewScores:[4],teacherMatchCount:0}); batch.delete(doc(d,'active_lesson_requests/coach_student'));
  await assertSucceeds(batch.commit());
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
  for(const uid of ['coach','admin']) await assertFails(updateDoc(doc(db(uid),'lesson_requests/lesson'),{reviewScore:5}));
});

test('original likeDelta/authorLikes/likes coupling remains supported without exposing private users', async () => {
  await seed('feed_videos/video',{...feed,createdAt:new Date()});
  const d=db('other'), video=doc(d,'feed_videos/video'), author=doc(d,'users/student'), like=doc(d,'feed_videos/video/likes/other');
  await assertFails(getDoc(author));
  await assertFails(updateDoc(video,{likes:1}));
  const add=writeBatch(d); add.update(video,{likes:1}); add.update(author,{feedLikeCount:1,lastFeedLikeVideoId:'video'}); add.set(like,{userId:'other',createdAt:serverTimestamp()});
  await assertSucceeds(add.commit());
  await assertFails(deleteDoc(like));
  const remove=writeBatch(d); remove.update(video,{likes:0}); remove.update(author,{feedLikeCount:0,lastFeedLikeVideoId:'video'}); remove.delete(like);
  await assertSucceeds(remove.commit());
});

test('original feature flag admin writes/types and upload shutdown are preserved', async () => {
  const adminConfig=doc(db('admin'),'app_config/features');
  await assertSucceeds(setDoc(adminConfig,{videoUploadsEnabled:false,paymentTestEnabled:false}));
  await assertSucceeds(getDoc(doc(db('student'),'app_config/features')));
  await assertFails(updateDoc(doc(db('student'),'app_config/features'),{videoUploadsEnabled:true}));
  await assertFails(updateDoc(adminConfig,{videoUploadsEnabled:'true'}));
  await assertFails(updateDoc(adminConfig,{paymentTestEnabled:'false'}));
  await assertFails(updateDoc(adminConfig,{unknownField:true}));
  await assertFails(setDoc(doc(db('student'),'feed_videos/disabled'),feed));
  await assertFails(uploadBytes(ref(store('student'),'videos/student/disabled.mp4'),bytes,{contentType:'video/mp4'}));
  // The original flag controls shortform uploads, not lesson feedback.
  await assertSucceeds(uploadBytes(ref(store('student'),'lesson_feedback/lesson/student/feedback.mp4'),bytes,{contentType:'video/mp4'}));
  await assertSucceeds(updateDoc(adminConfig,{videoUploadsEnabled:true,paymentTestEnabled:true}));
  await assertSucceeds(setDoc(doc(db('student'),'feed_videos/enabled'),feed));
});

test('original admin operation reads and all financial subcollections stay separated', async () => {
  await seed('account_admin_operations/student',{state:'completed'});
  await assertSucceeds(getDoc(doc(db('admin'),'account_admin_operations/student')));
  await assertSucceeds(getDocs(collection(db('admin'),'account_admin_operations')));
  for(const uid of ['student','coach','incomplete','missing','suspended','suspendedAdmin',null]) await assertFails(getDoc(doc(db(uid),'account_admin_operations/student')));
  await assertFails(setDoc(doc(db('admin'),'account_admin_operations/student'),{state:'forged'}));
  await assertFails(updateDoc(doc(db('admin'),'users/admin'),{role:'student',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('admin'),'users/suspended'),{role:'coach',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('admin'),'instructors/coach'),{name:'forged'}));
  await seed('payments/payment/refunds/refund',{amount:100});
  for(const uid of ['student','coach','admin',null]) {
    const r=doc(db(uid),'payments/payment/refunds/refund');
    await assertFails(getDoc(r)); await assertFails(setDoc(r,{amount:0}));
  }
});

test('both original report schemas and original text limits remain supported', async () => {
  const d=db('student');
  const legacy={reporterUid:'student',reportedUid:'coach',reportedUserName:'coach',reason:'r'.repeat(500),details:'d'.repeat(5000),timestamp:serverTimestamp(),status:'pending'};
  await assertSucceeds(setDoc(doc(d,'reports/legacy'),legacy));
  await assertFails(setDoc(doc(d,'reports/spoof'),{...legacy,reporterUid:'coach'}));
  const modern={reporterId:'student',reporterEmail:'student@example.test',reportedUserId:'coach',reportedUserName:'coach',reason:'r'.repeat(500),detail:'d'.repeat(5000),sanctionType:'OTHER',status:'PENDING',createdAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(d,'reports/modern'),modern));
  await assertFails(setDoc(doc(d,'reports/email-spoof'),{...modern,reporterEmail:'coach@example.test'}));
  await assertFails(setDoc(doc(d,'reports/long'),{...legacy,details:'d'.repeat(5001)}));
});

test('original 5000-character chat boundary survives preview integrity checks', async () => {
  const d=db('student'), room=doc(d,'chat_rooms/coach_student');
  const good='a'.repeat(5000), bad='a'.repeat(5001);
  const send=(id,text)=>{ const batch=writeBatch(d); batch.set(doc(d,`chat_rooms/coach_student/messages/${id}`),{senderId:'student',text,createdAt:serverTimestamp()}); batch.update(room,{lastMessage:text,lastMessageId:id,updatedAt:serverTimestamp()}); return batch.commit(); };
  await assertSucceeds(send('boundary',good));
  await assertFails(send('overlong',bad));
  assert.equal((await getDoc(room)).data().lastMessage,good);
  await assertFails(setDoc(doc(d,'chat_rooms/coach_student/messages/orphan'),{senderId:'student',text:'orphan',createdAt:serverTimestamp()}));
});

test('original PDF filename range and admin feedback read/delete rights are preserved', async () => {
  for(const id of ['A','Career_2026-1','a'.repeat(100)]) await assertSucceeds(uploadBytes(ref(store('incomplete'),`coach_documents/incomplete/${id}.pdf`),bytes,{contentType:'application/pdf'}));
  await assertFails(uploadBytes(ref(store('incomplete'),`coach_documents/incomplete/${'a'.repeat(101)}.pdf`),bytes,{contentType:'application/pdf'}));
  const path='lesson_feedback/lesson/student/moderated.mp4';
  await assertSucceeds(uploadBytes(ref(store('student'),path),bytes,{contentType:'video/mp4'}));
  await seed('lesson_requests/lesson/feedback_videos/moderated',{uploaderUid:'student',storagePath:path});
  await assertSucceeds(getDoc(doc(db('admin'),'lesson_requests/lesson/feedback_videos/moderated')));
  await assertSucceeds(getBytes(ref(store('admin'),path)));
  await assertFails(uploadBytes(ref(store('admin'),'lesson_feedback/lesson/admin/no.mp4'),bytes,{contentType:'video/mp4'}));
  await assertSucceeds(deleteObject(ref(store('admin'),path)));
  await assertSucceeds(uploadBytes(ref(store('student'),'videos/student/legacy.mkv'),bytes,{contentType:'video/x-matroska'}));
});

test('server completion keeps original approvedCoach and free-vs-priced restrictions', async () => {
  await seed('instructors/coach',{uid:'coach',name:'coach',sport:lesson.sport,status:'pending',signatureMove:'kick'});
  await assert.rejects(call('completeLesson','coach',{lessonId:'lesson',reviewScore:4,feedback:''}),{code:'permission-denied'});
  await seed('instructors/coach',{uid:'coach',name:'coach',sport:lesson.sport,status:'approved',signatureMove:'kick'});
  for(const fields of [{price:100},{paymentId:'payment'},{paymentRequired:true}]) {
    await seed('lesson_requests/priced',{...lesson,...fields});
    await assert.rejects(call('completeLesson','coach',{lessonId:'priced',reviewScore:4,feedback:''}),{code:'failed-precondition'});
  }
  for(const uid of ['missing','incomplete','suspended']) await assert.rejects(call('getPaymentStatus',uid,{paymentId:'payment'}),{code:'permission-denied'});
});

test('server admin and payment endpoints reject incomplete or suspended identities before Auth operations', async () => {
  await seed('users/incompleteAdmin',profile('incompleteAdmin',{role:'admin',profileCompleted:false}));
  for(const uid of ['student','coach','missing','incomplete','incompleteAdmin','suspended','suspendedAdmin']) {
    await assert.rejects(call('adminManageAccount',uid,{uid:'other',action:'suspend',reason:'emulator authorization test'}),{code:'permission-denied'});
  }
  await assert.rejects(call('adminManageAccount',null,{uid:'other',action:'suspend',reason:'emulator test'}),{code:'unauthenticated'});
  for(const uid of ['missing','incomplete','incompleteAdmin','suspended','suspendedAdmin']) await assert.rejects(call('getPaymentStatus',uid,{paymentId:'payment'}),{code:'permission-denied'});
});

test('server feedback moderation preserves admin deletion without allowing shortform takeover', async () => {
  const path='lesson_feedback/lesson/student/admin-delete.mp4';
  await assertSucceeds(uploadBytes(ref(store('student'),path),bytes,{contentType:'video/mp4'}));
  await seed('lesson_requests/lesson/feedback_videos/admin-delete',{uploaderUid:'student',storagePath:path});
  await call('deleteVideo','admin',{kind:'feedback',lessonId:'lesson',videoId:'admin-delete'});
  assert.equal((await getDoc(doc(db('admin'),'lesson_requests/lesson/feedback_videos/admin-delete'))).exists(),false);
  await assert.rejects(getBytes(ref(store('admin'),path)),{code:'storage/object-not-found'});
});

test('original-vs-hardened rules reproduce and close the identified vulnerabilities', async () => {
  const original=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,rules:readFileSync('../firestore.original.rules','utf8')},storage:{host:'127.0.0.1',port:9199,rules:readFileSync('../storage.original.rules','utf8')}});
  const saved=env;
  try {
    env=original;
    await assertSucceeds(getDoc(doc(db('other'),'users/student')));
    await assertSucceeds(getDoc(doc(db('missing'),'users/student')));
    await assertSucceeds(uploadBytes(ref(store('missing'),'videos/missing/clip.mp4'),bytes,{contentType:'video/mp4'}));
    const video=ref(store('student'),'videos/student/overwrite.mp4');
    await assertSucceeds(uploadBytes(video,bytes,{contentType:'video/mp4'}));
    await assertSucceeds(uploadBytes(video,new Uint8Array([4,5]),{contentType:'video/mp4'}));
    await assertSucceeds(updateDoc(doc(db('student'),'chat_rooms/coach_student'),{lastMessage:'unrelated',updatedAt:serverTimestamp()}));
    const report={reporterId:'student',reporterEmail:'forged@example.test',reportedUserId:'coach',reportedUserName:'coach',reason:'reason',detail:'',sanctionType:'OTHER',status:'PENDING',createdAt:serverTimestamp()};
    await assertSucceeds(setDoc(doc(db('student'),'reports/original-spoof'),report));
    const pending='lesson_feedback/pending/student/original.mp4';
    await seed('lesson_requests/pending',{...lesson,status:'pending'});
    await assertSucceeds(uploadBytes(ref(store('student'),pending),bytes,{contentType:'video/mp4'}));
    await assertSucceeds(setDoc(doc(db('student'),'feed_videos/original-spoof'),{...feed,userName:'forged',videoUrl:'https://example.test/forged.mp4'}));
  } finally {
    env=saved;
    await original.cleanup();
    const restore=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,rules:readFileSync('../firestore.rules','utf8')},storage:{host:'127.0.0.1',port:9199,rules:readFileSync('../storage.rules','utf8')}});
    await restore.cleanup();
  }
  await assertFails(getDoc(doc(db('other'),'users/student')));
  await assertFails(getDoc(doc(db('missing'),'users/student')));
  await assertFails(uploadBytes(ref(store('missing'),'videos/missing/another.mp4'),bytes,{contentType:'video/mp4'}));
  await assertFails(uploadBytes(ref(store('student'),'videos/student/overwrite.mp4'),bytes,{contentType:'video/mp4'}));
  await assertFails(updateDoc(doc(db('student'),'chat_rooms/coach_student'),{lastMessage:'forged again',updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db('student'),'reports/new-spoof'),{reporterId:'student',reporterEmail:'forged@example.test',reportedUserId:'coach',reportedUserName:'coach',reason:'reason',detail:'',sanctionType:'OTHER',status:'PENDING',createdAt:serverTimestamp()}));
  await assertFails(uploadBytes(ref(store('student'),'lesson_feedback/pending/student/hardened.mp4'),bytes,{contentType:'video/mp4'}));
  await assertFails(setDoc(doc(db('student'),'feed_videos/new-spoof'),{...feed,userName:'forged',videoUrl:'https://example.test/forged.mp4'}));
});
