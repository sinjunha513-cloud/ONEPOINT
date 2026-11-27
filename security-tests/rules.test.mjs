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
test('student recommendation preferences are owner-editable and validated', async () => {
  const own=doc(db('student'),'users/student');
  await assertSucceeds(updateDoc(own,{preferredSport:'축구',experienceLevel:'초급',learningGoal:'패스 자세',updatedAt:serverTimestamp()}));
  for(const fields of [{preferredSport:'invalid'},{experienceLevel:'프로'},{learningGoal:'a'.repeat(501)},{learningGoal:99}]) {
    await assertFails(updateDoc(own,{...fields,updatedAt:serverTimestamp()}));
  }
  await assertFails(updateDoc(doc(db('coach'),'users/student'),{learningGoal:'forged',updatedAt:serverTimestamp()}));
  assert.equal((await getDoc(own)).data().role,'student');
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
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/pending'),{status:'accepted',updatedAt:serverTimestamp()}));
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
  await assertFails(setDoc(r,data));
  await seed('reports/report',data);
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
  await assertFails(getBytes(ref(store('coach'),'videos/student/clip.mp4')));
  await assertSucceeds(getBytes(own)); await assertSucceeds(getBytes(ref(store('admin'),'videos/student/clip.mp4')));
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
const request = (uid,data) => ({auth:uid ? {uid,token:{email:`${uid}@example.test`,auth_time:Math.floor(Date.now()/1000)}} : undefined,data});
const call = async (name,uid,data) => {
  api ??= require('../functions/lib/src/index.js');
  if (['respondScheduleChange','respondLessonCompletion','resolveLessonDispute'].includes(name) && data.revision === undefined) {
    let lesson;
    await env.withSecurityRulesDisabled(async c=>{lesson=(await getDoc(doc(c.firestore(), 'lesson_requests/'+data.lessonId))).data();});
    data={...data,revision:Number(lesson?.[name==='respondScheduleChange'?'scheduleProposal':'completionReview']?.revision??0)};
  }
  return api[name].run(request(uid,data));
};

test('release: blocking is private and stops new bookings and atomic chat messages',async()=>{
  await call('setUserBlocked','student',{targetUid:'coach',blocked:true});
  await assertSucceeds(getDoc(doc(db('student'),'user_blocks/student/members/coach')));
  await assertFails(getDoc(doc(db('coach'),'user_blocks/student/members/coach')));
  await assertFails(setDoc(doc(db('student'),'user_blocks/coach/members/student'),{targetUid:'student'}));
  await assert.rejects(call('requestLesson','student',{instructorId:'coach'}),{code:'permission-denied'});
  const d=db('coach'),batch=writeBatch(d);
  batch.set(doc(d,'chat_rooms/coach_student/messages/blocked'),{senderId:'coach',text:'blocked',createdAt:serverTimestamp()});
  batch.update(doc(d,'chat_rooms/coach_student'),{lastMessage:'blocked',lastMessageId:'blocked',updatedAt:serverTimestamp()});
  await assertFails(batch.commit());
  await call('setUserBlocked','student',{targetUid:'coach',blocked:false});
  await call('requestLesson','student',{instructorId:'coach'});
});
test('release: reports bind real identities, retry once and require an administrator resolution',async()=>{
  const data={targetType:'user',targetId:'coach',reason:'언행 문제',details:'확인 요청',requestId:'request_1'};
  const report=await call('submitReport','student',data);
  assert.deepEqual(await call('submitReport','student',data),report);
  const stored=(await getDoc(doc(db('admin'),`reports/${report.reportId}`))).data();
  assert.equal(stored.reporterUid,'student');assert.equal(stored.reportedUserName,'coach');
  await assert.rejects(call('submitReport','student',{...data,reportedUid:'other'}),{code:'invalid-argument'});
  await assert.rejects(call('submitReport','student',{...data,targetId:'student',requestId:'self'}),{code:'invalid-argument'});
  await assert.rejects(call('resolveReport','student',{...report,decision:'warn',reason:'warn'}),{code:'permission-denied'});
  const results=await Promise.allSettled(Array.from({length:2},()=>call('resolveReport','admin',{...report,decision:'warn',reason:'운영 정책 안내'})));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal((await getDoc(doc(db('coach'),'users/coach'))).data().warningCount,1);
  await assertFails(updateDoc(doc(db('student'),`reports/${report.reportId}`),{status:'resolved'}));
});
test('release: public feed is redacted, hidden on moderation, and playback checks participation',async()=>{
  await seed('feed_videos/review',{...feed,userId:'coach',userName:'forged',storagePath:'videos/coach/clip.mp4',videoUrl:'videos/coach/clip.mp4',createdAt:new Date(),email:'private@example.test'});
  const community=require('../functions/lib/src/community.js');await community.projectFeed('review');
  const pub=(await getDoc(doc(db('student'),'public_feed_videos/review'))).data();
  assert.equal(pub.userName,'coach');assert.equal(pub.email,undefined);
  await assertFails(getDoc(doc(db('student'),'feed_videos/review')));
  const media=require('../functions/lib/src/media_playback.js');
  assert.equal(await media.authorizedMediaPath('student',{kind:'feed',videoId:'review'}),'videos/coach/clip.mp4');
  const report=await call('submitReport','student',{targetType:'feed',targetId:'review',reason:'부적절한 영상',details:'',requestId:'video_1'});
  await call('resolveReport','admin',{...report,decision:'hide',reason:'운영 정책 위반'});
  assert.equal((await getDoc(doc(db('student'),'public_feed_videos/review'))).exists(),false);
  await community.projectFeed('review');
  assert.equal((await getDoc(doc(db('student'),'public_feed_videos/review'))).exists(),false);
  await assert.rejects(media.authorizedMediaPath('student',{kind:'feed',videoId:'review'}),{code:'permission-denied'});
  assert.equal(await media.authorizedMediaPath('admin',{kind:'feed',videoId:'review'}),'videos/coach/clip.mp4');
  await seed('lesson_requests/lesson/feedback_videos/private',{uploaderUid:'student',storagePath:'lesson_feedback/lesson/student/clip.mp4'});
  await assert.rejects(media.authorizedMediaPath('other',{kind:'feedback',lessonId:'lesson',videoId:'private'}),{code:'permission-denied'});
  assert.equal(await media.authorizedMediaPath('coach',{kind:'feedback',lessonId:'lesson',videoId:'private'}),'lesson_feedback/lesson/student/clip.mp4');
  await seed('feed_videos/incomplete-author',{...feed,userId:'incomplete',storagePath:'videos/incomplete/clip.mp4'});
  await assert.rejects(call('setFeedLiked','student',{videoId:'incomplete-author',liked:true}),{code:'failed-precondition'});
});
const nativeDevice=n=>({provider:'fcm',token:'test_registration_token_'+String(n).padStart(25,'a')});
test('release: push registrations transfer safely, reject arbitrary URLs and remain server-private',async()=>{
  const device=await call('registerPushDevice','student',nativeDevice(1));
  for(const uid of ['student','coach','admin',null])await assertFails(getDoc(doc(db(uid),`push_devices/${device.deviceId}`)));
  await call('registerPushDevice','coach',nativeDevice(1));
  await call('unregisterPushDevice','student',device);
  await env.withSecurityRulesDisabled(async c=>assert.equal((await getDoc(doc(c.firestore(),`push_devices/${device.deviceId}`))).data().uid,'coach'));
  await assert.rejects(call('registerPushDevice','student',{provider:'web',subscription:{endpoint:'https://127.0.0.1/private',keys:{}}}),{code:'invalid-argument'});
  await assert.rejects(call('registerPushDevice','suspended',nativeDevice(2)),{code:'permission-denied'});
  for(let n=2;n<=12;n++)await call('registerPushDevice','student',nativeDevice(n));
  await env.withSecurityRulesDisabled(async c=>assert.equal((await getDocs(query(collection(c.firestore(),'push_devices'),where('uid','==','student')))).size,10));
  await call('setPushPreference','student',{enabled:false});
  await env.withSecurityRulesDisabled(async c=>assert.equal((await getDocs(query(collection(c.firestore(),'push_devices'),where('uid','==','student')))).size,0));
});
test('release: live push is idempotent, hides previews, removes invalid devices and skips history/blocked users',async()=>{
  const a=await call('registerPushDevice','student',nativeDevice(1));
  const b=await call('registerPushDevice','student',nativeDevice(2));
  await call('setPushPreference','student',{previews:false});
  const notice={kind:'lesson',title:'레슨',body:'private preview',createdAt:new Date(),pushEligible:true,readAt:null};
  await seed('users/student/notifications/live',notice);
  const module=require('../functions/lib/src/push_delivery.js'),sent=[];
  const io={web:async()=>{},fcm:async(token,payload)=>{if(token===nativeDevice(2).token)throw Object.assign(Error('expired'),{code:'messaging/registration-token-not-registered'});sent.push(payload);}};
  await module.deliverPush('student','live',io);await module.deliverPush('student','live',io);
  assert.equal(sent.length,1);assert.equal(sent[0].body,'새 알림이 도착했습니다.');
  await env.withSecurityRulesDisabled(async c=>{assert.equal((await getDoc(doc(c.firestore(),`push_devices/${a.deviceId}`))).exists(),true);assert.equal((await getDoc(doc(c.firestore(),`push_devices/${b.deviceId}`))).exists(),false);});
  await seed('users/student/notifications/history',{...notice,pushEligible:false});
  await module.deliverPush('student','history',io);assert.equal(sent.length,1);
  await call('setUserBlocked','student',{targetUid:'coach',blocked:true});
  await seed('users/student/notifications/blocked',{...notice,kind:'chat',sourceUid:'coach'});
  await module.deliverPush('student','blocked',io);assert.equal(sent.length,1);
});
test('release: withdrawal requires fresh reauthentication and completed responsibilities',async()=>{
  await assert.rejects(call('requestAccountDeletion','student',{confirmation:'회원탈퇴'}),{code:'failed-precondition'});
  await assert.rejects(call('requestAccountDeletion','admin',{confirmation:'회원탈퇴'}),{code:'failed-precondition'});
  await assert.rejects(api.requestAccountDeletion.run({auth:{uid:'other',token:{auth_time:Math.floor(Date.now()/1000)-600}},data:{confirmation:'회원탈퇴'}}),{code:'failed-precondition'});
  await assert.rejects(call('requestAccountDeletion','other',{confirmation:'회원탈퇴',uid:'student'}),{code:'invalid-argument'});
  await call('requestAccountDeletion','other',{confirmation:'회원탈퇴'});
  assert.equal((await getDoc(doc(db('other'),'users/other'))).data().accountStatus,'deleting');
  await assertFails(setDoc(doc(db('other'),'users/other'),profile('other')));
  await assertFails(setDoc(doc(db('student'),'account_deletions/student'),{phase:13}));
});
test('release: queued withdrawal removes owned data, preserves a blocked tombstone and anonymizes shared records',async()=>{
  await seed('feed_videos/owned',{...feed,userId:'other',createdAt:new Date(),storagePath:'videos/other/clip.mp4'});
  await seed('public_feed_videos/owned',{userId:'other'});
  await seed('chat_rooms/other_student',{participantIds:['other','student'],studentUid:'other',coachUid:'student',studentName:'Personal Name',lastMessage:'private text',lastMessageId:'msg'});
  await seed('chat_rooms/other_student/messages/msg',{senderId:'other',text:'private text',createdAt:new Date()});
  await seed('users/other/notifications/old',{body:'private'});
  await seed('user_blocks/student/members/other',{targetUid:'other',name:'Personal Name'});
  await seed('users/student/notifications/other_old',{targetId:'other_student',body:'private text',targetName:'Personal Name'});
  await seed('lesson_requests/old_other',{...lesson,studentUid:'other',studentName:'Personal Name',participantIds:['other','coach'],status:'completed',completedAt:new Date(Date.now()-10000)});
  await call('requestAccountDeletion','other',{confirmation:'회원탈퇴'});
  const cleaned=[];
  const io={disableAuth:async uid=>cleaned.push('disabled:'+uid),deleteAuth:async uid=>{assert.equal((await getDoc(doc(db('admin'),`users/${uid}`))).data().accountStatus,'deleted');cleaned.push('auth:'+uid);},deleteFile:async p=>cleaned.push(p),deletePrefix:async p=>{cleaned.push(p);return true;}};
  await require('../functions/lib/src/account_lifecycle.js').processAccountDeletion('other',io);
  const user=(await getDoc(doc(db('admin'),'users/other'))).data();assert.equal(user.email,undefined);assert.equal(user.name,'탈퇴한 회원');
  await assertFails(updateDoc(doc(db('other'),'users/other'),{accountStatus:'active',profileCompleted:true}));
  await env.withSecurityRulesDisabled(async c=>{
    assert.equal((await getDoc(doc(c.firestore(),'account_deletions/other'))).data().status,'done');
    assert.equal((await getDoc(doc(c.firestore(),'feed_videos/owned'))).exists(),false);
    assert.equal((await getDoc(doc(c.firestore(),'chat_rooms/other_student/messages/msg'))).exists(),false);
    assert.equal((await getDoc(doc(c.firestore(),'users/other/notifications/old'))).exists(),false);
    assert.equal((await getDoc(doc(c.firestore(),'user_blocks/student/members/other'))).exists(),false);
  });
  assert.equal((await getDoc(doc(db('student'),'chat_rooms/other_student'))).data().studentName,'탈퇴한 회원');
  assert.equal((await getDoc(doc(db('student'),'users/student/notifications/other_old'))).data().targetName,'탈퇴한 회원');
  assert.equal((await getDoc(doc(db('coach'),'lesson_requests/old_other'))).data().studentName,'탈퇴한 회원');
  assert.ok(cleaned.includes('auth:other'));
});
test('release: activity counters use role-specific real completions and cannot be client inflated',async()=>{
  await seed('lesson_requests/completed_a',{...lesson,status:'completed',completedAt:new Date(Date.now()-1000)});
  await seed('lesson_requests/completed_b',{...lesson,studentUid:'coach',instructorUid:'other',participantIds:['coach','other'],status:'completed',completedAt:new Date(Date.now()-1000)});
  await seed('lesson_requests/future_bad',{...lesson,status:'completed',completedAt:new Date(Date.now()-1000),scheduledEndAt:new Date(Date.now()+86400000)});
  await call('syncMyActivity','coach',{});await call('syncMyActivity','student',{});
  const stats=require('../functions/lib/src/activity_stats.js');await Promise.all([stats.rebuildActivity('coach',true),stats.rebuildActivity('coach',true)]);
  const coach=(await getDoc(doc(db('coach'),'users/coach'))).data(),student=(await getDoc(doc(db('student'),'users/student'))).data();
  assert.equal(coach.completedTeachingCount,1);assert.equal(coach.completedLearningCount,1);assert.equal(student.completedLearningCount,1);
  await assertFails(updateDoc(doc(db('coach'),'users/coach'),{completedTeachingCount:100,activityVersion:1,updatedAt:serverTimestamp()}));
});

async function workflowSlot(coach='coach', offset=0) {
  const start=Date.now()+2*86400000+offset*3600000;
  return call('saveAvailabilitySlot',coach,{startAtMillis:start,endAtMillis:start+3600000});
}
async function pastLesson(id,extra={}) {
  await seed(`lesson_requests/${id}`,{...lesson,scheduledStartAt:new Date(Date.now()-7200000),scheduledEndAt:new Date(Date.now()-3600000),...extra});
}
test('workflow: same coach accepts multiple dates and concurrent cross-coach overlaps have one winner', async()=>{
  const a=await workflowSlot(),b=await workflowSlot('coach',2);
  const first=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:a.slotId});
  await call('acceptLesson','coach',first);
  await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:b.slotId});
  await seed('users/teacher',profile('teacher',{role:'coach'}));
  await seed('instructors/teacher',{uid:'teacher',userId:'teacher',name:'teacher',sport:'축구',status:'approved'});
  const start=Date.now()+4*86400000;
  const slots=await Promise.all(['coach','teacher'].map(uid=>call('saveAvailabilitySlot',uid,{startAtMillis:start,endAtMillis:start+3600000})));
  const booked=await Promise.allSettled(['coach','teacher'].map((uid,i)=>call('requestLessonWithSlot','student',{instructorId:uid,slotId:slots[i].slotId})));
  assert.equal(booked.filter(r=>r.status==='fulfilled').length,1);
  const crossStart=Date.now()+7*86400000;
  const teaching=await call('saveAvailabilitySlot','coach',{startAtMillis:crossStart,endAtMillis:crossStart+3600000});
  const learning=await call('saveAvailabilitySlot','teacher',{startAtMillis:crossStart,endAtMillis:crossStart+3600000});
  await call('requestLessonWithSlot','coach',{instructorId:'teacher',slotId:learning.slotId});
  await assert.rejects(call('requestLessonWithSlot','other',{instructorId:'coach',slotId:teaching.slotId}),{code:'already-exists'});
});
test('workflow: accepted cancellation requires reason and releases the precise slot',async()=>{
  const slot=await workflowSlot(),booking=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:slot.slotId});
  await call('acceptLesson','coach',booking);
  await assert.rejects(call('cancelLesson','other',{...booking,reason:'not mine'}),{code:'permission-denied'});
  await assert.rejects(call('cancelLesson','student',booking),{code:'invalid-argument'});
  await call('cancelLesson','student',{...booking,reason:'일정 취소'});
  assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${slot.slotId}`))).data().status,'available');
  const next=await call('requestLessonWithSlot','other',{instructorId:'coach',slotId:slot.slotId});
  const {releaseClosedLesson}=require('../functions/lib/src/lesson_workflow.js');await releaseClosedLesson(booking.lessonId);
  assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${slot.slotId}`))).data().lessonId,next.lessonId);
});
test('workflow: date proposal holds new time, requires the other party and atomically swaps after approval',async()=>{
  const a=await workflowSlot(),b=await workflowSlot('coach',2),booking=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:a.slotId});
  await call('acceptLesson','coach',booking);
  await call('rescheduleLesson','student',{...booking,slotId:b.slotId});
  const path=`lesson_requests/${booking.lessonId}`;
  assert.equal((await getDoc(doc(db('student'),path))).data().slotId,a.slotId);
  assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${b.slotId}`))).data().status,'held');
  await assert.rejects(call('respondScheduleChange','student',{...booking,decision:'approve'}),{code:'permission-denied'});
  await assert.rejects(call('requestLessonWithSlot','other',{instructorId:'coach',slotId:b.slotId}),{code:'failed-precondition'});
  await assert.rejects(call('respondScheduleChange','coach',{...booking,decision:'approve',revision:0}),{code:'failed-precondition'});
  await call('respondScheduleChange','coach',{...booking,decision:'approve'});
  assert.equal((await getDoc(doc(db('student'),path))).data().slotId,b.slotId);
  assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${a.slotId}`))).data().status,'available');
  const history=await getDocs(collection(db('student'),path+'/schedule_changes'));assert.equal(history.size,1);
});
test('workflow: rejected, withdrawn and expired proposals retain original booking and release holds',async()=>{
  const a=await workflowSlot(),b=await workflowSlot('coach',2),booking=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:a.slotId});
  await call('acceptLesson','coach',booking);
  for(const decision of ['reject','withdraw','expire']) {
    await call('rescheduleLesson','student',{...booking,slotId:b.slotId});
    if(decision==='expire') {
      await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),`lesson_requests/${booking.lessonId}`),{'scheduleProposal.expiresAt':new Date(Date.now()-1000)}));
      await require('../functions/lib/src/lesson_workflow.js').expireLesson(booking.lessonId);
    }else await call('respondScheduleChange',decision==='reject'?'coach':'student',{...booking,decision});
    assert.equal((await getDoc(doc(db('student'),`lesson_requests/${booking.lessonId}`))).data().slotId,a.slotId);
    assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${b.slotId}`))).data().status,'available');
  }
});
test('workflow: overdue pending request expires before acceptance and frees resources; paid records are untouched',async()=>{
  const a=await workflowSlot(),booking=await call('requestLessonWithSlot','student',{instructorId:'coach',slotId:a.slotId});
  await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),`lesson_requests/${booking.lessonId}`),{expiresAt:new Date(Date.now()-1000)}));
  await assert.rejects(call('acceptLesson','coach',booking),{code:'failed-precondition'});
  assert.equal((await getDoc(doc(db('student'),`lesson_requests/${booking.lessonId}`))).data().status,'expired');
  assert.equal((await getDoc(doc(db('coach'),`instructors/coach/availability/${a.slotId}`))).data().status,'available');
  await seed('lesson_requests/paid_expiry',{...lesson,status:'pending',price:50000,expiresAt:new Date(0)});
  await require('../functions/lib/src/lesson_workflow.js').expireLesson('paid_expiry');
  assert.equal((await getDoc(doc(db('student'),'lesson_requests/paid_expiry'))).data().status,'pending');
});
test('workflow: only ended lessons can request completion and only student confirmation awards once',async()=>{
  await seed('lesson_requests/future',{...lesson,scheduledStartAt:new Date(Date.now()+3600000),scheduledEndAt:new Date(Date.now()+7200000)});
  await assert.rejects(call('completeLesson','coach',{lessonId:'future',reviewScore:4,feedback:''}),{code:'failed-precondition'});
  await pastLesson('ended');
  await call('completeLesson','coach',{lessonId:'ended',reviewScore:4,feedback:'확인'});
  assert.equal((await getDoc(doc(db('student'),'lesson_requests/ended'))).data().status,'accepted');
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
  await assert.rejects(call('respondLessonCompletion','coach',{lessonId:'ended',decision:'confirm'}),{code:'permission-denied'});
  await Promise.all(Array.from({length:3},()=>call('respondLessonCompletion','student',{lessonId:'ended',decision:'confirm'})));
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
  assert.equal((await getDoc(doc(db('student'),'lesson_requests/ended'))).data().attendanceBadge.signatureMove,'kick');
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/ended'),{status:'accepted'}));
});

test('unpaid test mode: ended quote can be evaluated and confirmed once without payment or settlement',async()=>{
  await seed('app_config/features',{lessonTestModeEnabled:true});
  await pastLesson('test_quote');
  await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'lesson_requests/test_quote'),{price:50000,paymentRequired:true}));
  await assert.rejects(call('completeLesson','student',{lessonId:'test_quote',reviewScore:4,feedback:''}),{code:'permission-denied'});
  await call('completeLesson','coach',{lessonId:'test_quote',reviewScore:4,feedback:'테스트 평가'});
  let record=(await getDoc(doc(db('student'),'lesson_requests/test_quote'))).data();
  assert.equal(record.status,'accepted');assert.equal(record.completionReview.testWithoutPayment,true);
  assert.equal(record.paymentStatus,undefined);assert.equal(record.paymentId,undefined);
  await assertFails(updateDoc(doc(db('coach'),'lesson_requests/test_quote'),{'completionReview.testWithoutPayment':false}));
  await Promise.all(Array.from({length:3},()=>call('respondLessonCompletion','student',{lessonId:'test_quote',decision:'confirm'})));
  record=(await getDoc(doc(db('student'),'lesson_requests/test_quote'))).data();
  assert.equal(record.status,'completed');assert.equal(record.reviewScore,4);assert.equal(record.price,50000);
  assert.equal(record.paymentStatus,undefined);assert.equal(record.paymentId,undefined);
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
  await env.withSecurityRulesDisabled(async c=>{
    assert.equal((await getDocs(collection(c.firestore(),'payments'))).size,0);
    assert.equal((await getDocs(collection(c.firestore(),'settlements'))).size,0);
  });
});

test('regression: Korean-badge completion uses the catalog ID through student confirmation',async()=>{
  await seed('app_config/features',{lessonTestModeEnabled:true});
  await seed('signature_badges/라크로케타',{name:'라크로케타',normalizedName:'라크로케타',colorIndex:7,sequence:0});
  await seed('instructors/coach',{uid:'coach',userId:'coach',name:'coach',sport:'축구',status:'approved',signatureMove:'라크로케타',signatureBadgeId:'라크로케타',signatureBadgeColorIndex:7});
  await pastLesson('korean_badge_lesson');
  await call('completeLesson','coach',{lessonId:'korean_badge_lesson',reviewScore:4,feedback:'한글 뱃지 평가',signatureMove:'라크로케타'});
  let record=(await getDoc(doc(db('student'),'lesson_requests/korean_badge_lesson'))).data();
  assert.equal(record.completionReview.status,'pending');
  assert.equal(record.completionReview.attendanceBadge.signatureBadgeId,'라크로케타');
  assert.equal(record.completionReview.testWithoutPayment,true);
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
  await call('respondLessonCompletion','student',{lessonId:'korean_badge_lesson',decision:'confirm'});
  record=(await getDoc(doc(db('student'),'lesson_requests/korean_badge_lesson'))).data();
  assert.equal(record.status,'completed');assert.equal(record.reviewScore,4);
  assert.equal(record.attendanceBadge.signatureBadgeId,'라크로케타');
  assert.equal(record.attendanceBadge.signatureMove,'라크로케타');
  assert.equal(record.attendanceBadge.signatureBadgeColorIndex,7);
  await call('respondLessonCompletion','student',{lessonId:'korean_badge_lesson',decision:'confirm'});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
});

test('unpaid test mode: server flag, end time, dates and real payment isolation remain required',async()=>{
  await pastLesson('test_quote');
  await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'lesson_requests/test_quote'),{price:50000}));
  await assert.rejects(call('completeLesson','coach',{lessonId:'test_quote',reviewScore:4,feedback:''}),{code:'failed-precondition'});
  await assertFails(setDoc(doc(db('student'),'app_config/features'),{lessonTestModeEnabled:true}));
  await assertSucceeds(setDoc(doc(db('admin'),'app_config/features'),{lessonTestModeEnabled:true}));
  await assertFails(updateDoc(doc(db('coach'),'app_config/features'),{lessonTestModeEnabled:false}));
  await assert.rejects(call('completeLesson','coach',{lessonId:'test_quote',reviewScore:4,feedback:'',testWithoutPayment:true}),{code:'invalid-argument'});
  for(const [id,fields] of Object.entries({
    future:{scheduledStartAt:new Date(Date.now()+3600000),scheduledEndAt:new Date(Date.now()+7200000)},
    missing:{},linked:{paymentId:'real_payment'},paid:{paymentStatus:'paid'},orphan:{}
  })){
    const schedule=['missing'].includes(id)?{}:{scheduledStartAt:new Date(Date.now()-7200000),scheduledEndAt:new Date(Date.now()-3600000)};
    await seed('lesson_requests/'+id,{...lesson,price:50000,...schedule,...fields});
    if(id==='orphan')await seed('payments/orphan_payment',{lessonId:id,paymentStatus:'pending'});
    await assert.rejects(call('completeLesson','coach',{lessonId:id,reviewScore:4,feedback:''}),{code:'failed-precondition'});
  }
  await call('completeLesson','coach',{lessonId:'test_quote',reviewScore:4,feedback:''});
  await seed('payments/racing_payment',{lessonId:'test_quote',paymentStatus:'pending'});
  await assert.rejects(call('respondLessonCompletion','student',{lessonId:'test_quote',decision:'confirm'}),{code:'failed-precondition'});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
});
test('workflow: disputed attendance blocks awards and requires an audited admin decision',async()=>{
  await pastLesson('disputed');
  await call('completeLesson','coach',{lessonId:'disputed',reviewScore:4,feedback:''});
  await call('respondLessonCompletion','student',{lessonId:'disputed',decision:'dispute',reason:'진행 내용이 다릅니다'});
  await assert.rejects(call('completeLesson','coach',{lessonId:'disputed',reviewScore:4,feedback:''}),{code:'failed-precondition'});
  await assert.rejects(call('respondLessonCompletion','student',{lessonId:'disputed',decision:'confirm'}),{code:'failed-precondition'});
  await assert.rejects(call('resolveLessonDispute','coach',{lessonId:'disputed',decision:'confirm',reason:'검토'}),{code:'permission-denied'});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
  await call('resolveLessonDispute','admin',{lessonId:'disputed',decision:'confirm',reason:'참여 자료 확인'});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
  const audit=await getDocs(collection(db('admin'),'lesson_requests/disputed/workflow_history'));assert.equal(audit.size,3);
  await assertFails(getDocs(collection(db('other'),'lesson_requests/disputed/workflow_history')));
});
test('workflow: no-show dispute can be reopened or cancelled without fabricated coach awards',async()=>{
  await pastLesson('noshow');
  await call('respondLessonCompletion','student',{lessonId:'noshow',decision:'dispute',reason:'코치 미참여'});
  await assert.rejects(call('resolveLessonDispute','admin',{lessonId:'noshow',decision:'confirm',reason:'확인'}),{code:'failed-precondition'});
  await call('resolveLessonDispute','admin',{lessonId:'noshow',decision:'reopen',reason:'재협의'});
  await call('respondLessonCompletion','student',{lessonId:'noshow',decision:'dispute',reason:'협의되지 않음'});
  await call('resolveLessonDispute','admin',{lessonId:'noshow',decision:'cancel',reason:'미진행 확인'});
  assert.equal((await getDoc(doc(db('student'),'lesson_requests/noshow'))).data().status,'cancelled');
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
});

test('workflow: reopened completion keeps increasing revisions and rejects stale confirmation',async()=>{
  await pastLesson('redo');
  await call('completeLesson','coach',{lessonId:'redo',reviewScore:4,feedback:''});
  await call('respondLessonCompletion','student',{lessonId:'redo',decision:'dispute',reason:'확인 필요'});
  await call('resolveLessonDispute','admin',{lessonId:'redo',decision:'reopen',reason:'다시 확인'});
  await call('completeLesson','coach',{lessonId:'redo',reviewScore:5,feedback:'재확인'});
  const review=(await getDoc(doc(db('student'),'lesson_requests/redo'))).data().completionReview;
  assert.equal(review.revision,3);
  await assert.rejects(call('respondLessonCompletion','student',{lessonId:'redo',decision:'confirm',revision:1}),{code:'failed-precondition'});
  await call('respondLessonCompletion','student',{lessonId:'redo',decision:'confirm',revision:3});
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,1);
});

const couponMonth = () => {
  const date=new Date(Date.now()+9*3600000);
  return `${date.getUTCFullYear()}${String(date.getUTCMonth()+1).padStart(2,'0')}`;
};
const availableCoupon = (extra={}) => ({kind:'monthly_goal',earnedRole:'student',rate:10,earnedMonth:couponMonth(),status:'available',
  issuedAt:new Date(),expiresAt:new Date(Date.now()+30*86400000),reservedLessonId:null,reservedAt:null,usedAt:null,...extra});
async function completedLessons(uid,role,count) {
  for(let i=0;i<count;i++) await seed(`lesson_requests/reward_${uid}_${i}`,{...lesson,
    studentUid:role==='student'?uid:'other',instructorUid:role==='coach'?uid:'reward_teacher',
    participantIds:[uid,'other'],status:'completed',completedAt:new Date(Date.now()-1000)});
}
test('monthly reward: only students with 20 real completions, one claim per month and no caller counts', async () => {
  await completedLessons('student','student',9);
  await seed('lesson_requests/old_reward',{...lesson,status:'completed',completedAt:new Date('2020-01-01')});
  await seed('lesson_requests/missing_time',{...lesson,status:'completed'});
  await assert.rejects(call('claimMonthlyCoupon','student',{}),{code:'failed-precondition'});
  await assert.rejects(call('claimMonthlyCoupon','student',{count:10}),{code:'invalid-argument'});
  await seed('lesson_requests/reward_student_9',{...lesson,status:'completed',completedAt:new Date(Date.now()-1000)});
  await assert.rejects(call('claimMonthlyCoupon','student',{}),{code:'failed-precondition'});
  await completedLessons('student','student',19);
  await assert.rejects(call('claimMonthlyCoupon','student',{}),{code:'failed-precondition'});
  await seed('lesson_requests/reward_student_19',{...lesson,status:'completed',completedAt:new Date(Date.now()-1000)});
  const results=await Promise.all(Array.from({length:4},()=>call('claimMonthlyCoupon','student',{})));
  assert.equal(results.filter(r=>!r.alreadyClaimed).length,1);
  const coupons=await getDocs(collection(db('student'),'users/student/coupons'));
  assert.equal(coupons.size,1);
  const coupon=coupons.docs[0].data();
  assert.equal(coupon.expiresAt.toMillis()-coupon.issuedAt.toMillis(),30*86400000);
  assert.equal(coupon.goalTarget,20);
  assert.equal(coupon.earnedRole,'student');
  await seed('users/student',profile('student',{role:'coach'}));
  await assert.rejects(call('claimMonthlyCoupon','student',{}),{code:'permission-denied'});
  await completedLessons('coach','student',20);
  await assert.rejects(call('claimMonthlyCoupon','coach',{}),{code:'permission-denied'});
  await completedLessons('coach','coach',20);
  await assert.rejects(call('claimMonthlyCoupon','coach',{}),{code:'permission-denied'});
  for(const uid of [null,'suspended','incomplete']) await assert.rejects(call('claimMonthlyCoupon',uid,{}));
});
test('coupon privacy and immutable client state includes admin and participants', async () => {
  await seed('users/student/coupons/monthly_test',availableCoupon());
  await assertSucceeds(getDocs(collection(db('student'),'users/student/coupons')));
  for(const uid of ['coach','other','admin',null]) await assertFails(getDoc(doc(db(uid),'users/student/coupons/monthly_test')));
  for(const uid of ['student','admin']) {
    await assertFails(updateDoc(doc(db(uid),'users/student/coupons/monthly_test'),{status:'available'}));
    await assertFails(setDoc(doc(db(uid),'users/student/coupons/forged'),availableCoupon()));
    await assertFails(deleteDoc(doc(db(uid),'users/student/coupons/monthly_test')));
  }
});
test('coupon applies once, keeps coach payout, supports removal, and locks at payment preparation', async () => {
  await seed('users/student/coupons/monthly_test',availableCoupon());
  await seed('lesson_requests/paid_lesson',{...lesson,price:50000,currency:'KRW'});
  await seed('lesson_requests/second_paid',{...lesson,price:30000,currency:'KRW'});
  await seed('users/student/coupons/old_coach',availableCoupon({earnedRole:'coach'}));
  await assert.rejects(call('applyLessonCoupon','student',{lessonId:'paid_lesson',couponId:'old_coach'}),{code:'failed-precondition'});
  await seed('users/coach/coupons/old_coach',availableCoupon({earnedRole:'coach'}));
  await seed('lesson_requests/coach_learning',{...lesson,studentUid:'coach',instructorUid:'teacher',participantIds:['coach','teacher'],price:50000,currency:'KRW'});
  await assert.rejects(call('applyLessonCoupon','coach',{lessonId:'coach_learning',couponId:'old_coach'}),{code:'permission-denied'});
  await assert.rejects(call('applyLessonCoupon','other',{lessonId:'paid_lesson',couponId:'monthly_test'}),{code:'permission-denied'});
  await assert.rejects(call('applyLessonCoupon','student',{lessonId:'paid_lesson',couponId:'monthly_test',price:1}),{code:'invalid-argument'});
  await call('applyLessonCoupon','student',{lessonId:'paid_lesson',couponId:'monthly_test'});
  const discounted=(await getDoc(doc(db('student'),'lesson_requests/paid_lesson'))).data();
  assert.equal(discounted.price,45000);assert.equal(discounted.coachAmount,44000);assert.equal(discounted.platformFee,1000);
  assert.equal((await call('applyLessonCoupon','student',{lessonId:'paid_lesson',couponId:'monthly_test'})).price,45000);
  await assert.rejects(call('applyLessonCoupon','student',{lessonId:'second_paid',couponId:'monthly_test'}),{code:'failed-precondition'});
  await seed('users/student',profile('student',{role:'coach'}));
  await call('removeLessonCoupon','student',{lessonId:'paid_lesson'});
  await seed('users/student',profile('student'));
  assert.equal((await getDoc(doc(db('student'),'lesson_requests/paid_lesson'))).data().price,50000);
  assert.equal((await getDoc(doc(db('student'),'users/student/coupons/monthly_test'))).data().status,'available');
  await call('applyLessonCoupon','student',{lessonId:'second_paid',couponId:'monthly_test'});
  const adminRequire=createRequire(new URL('../functions/package.json',import.meta.url));
  const {getFirestore}=adminRequire('firebase-admin/firestore');
  const {FirestorePaymentStore}=require('../functions/lib/src/store.js');
  const {PaymentService}=require('../functions/lib/src/payment_service.js');
  const prepared=await new PaymentService(new FirestorePaymentStore(getFirestore())).prepare('student','second_paid',{platformFeeBps:2000});
  assert.equal(prepared.amount,27000);assert.equal(prepared.coachAmount,26400);assert.equal(prepared.platformFee,600);
  assert.equal(prepared.couponId,'monthly_test');
  await assert.rejects(call('removeLessonCoupon','student',{lessonId:'second_paid'}),{code:'failed-precondition'});
});
test('expired coupons cannot apply; concurrent reservations have one winner', async () => {
  await seed('users/student/coupons/expired',availableCoupon({expiresAt:new Date(Date.now()-1000)}));
  for(const id of ['a','b']) await seed(`lesson_requests/${id}`,{...lesson,price:10009,currency:'KRW'});
  await assert.rejects(call('applyLessonCoupon','student',{lessonId:'a',couponId:'expired'}),{code:'failed-precondition'});
  await seed('users/student/coupons/one',availableCoupon());
  const results=await Promise.allSettled(['a','b'].map(lessonId=>call('applyLessonCoupon','student',{lessonId,couponId:'one'})));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
});
test('coupon reconciliation reads current state, releases unpaid cancellation and never restores paid use', async () => {
  const {reconcileLessonCoupon}=require('../functions/lib/src/coupons.js');
  await seed('users/student/coupons/one',availableCoupon());
  await seed('lesson_requests/a',{...lesson,price:50000,currency:'KRW'});
  await call('applyLessonCoupon','student',{lessonId:'a',couponId:'one'});
  await seed('lesson_requests/a',{...lesson,status:'cancelled',couponId:'one'});
  await reconcileLessonCoupon('a');await reconcileLessonCoupon('a');
  assert.equal((await getDoc(doc(db('student'),'users/student/coupons/one'))).data().status,'available');
  await seed('lesson_requests/b',{...lesson,price:50000,currency:'KRW'});
  await call('applyLessonCoupon','student',{lessonId:'b',couponId:'one'});
  await reconcileLessonCoupon('a'); // delayed older event must not release b's reservation
  assert.equal((await getDoc(doc(db('student'),'users/student/coupons/one'))).data().reservedLessonId,'b');
  await seed('lesson_requests/b',{...lesson,status:'confirmed',couponId:'one',paymentId:'pay'});
  await seed('payments/pay',{lessonId:'b',couponId:'one',studentUid:'student',paymentStatus:'paid',paidAt:new Date()});
  await reconcileLessonCoupon('b');
  assert.equal((await getDoc(doc(db('student'),'users/student/coupons/one'))).data().status,'used');
  await seed('lesson_requests/b',{...lesson,status:'cancelled',couponId:'one',paymentId:'pay'});
  await seed('payments/pay',{lessonId:'b',couponId:'one',paymentStatus:'refunded',paidAt:new Date()});
  await reconcileLessonCoupon('b');
  assert.equal((await getDoc(doc(db('student'),'users/student/coupons/one'))).data().status,'used');
});
test('server workflows: booking, acceptance/chat creation, completion, idempotent likes and public projection', async () => {
  const {lessonId}=await call('requestLesson','student',{instructorId:'coach'});
  await assert.rejects(call('requestLesson','student',{instructorId:'coach'}),{code:'already-exists'});
  await call('acceptLesson','coach',{lessonId});
  await seed(`lesson_requests/${lessonId}`,{...(await getDoc(doc(db('student'),`lesson_requests/${lessonId}`))).data(),scheduledStartAt:new Date(Date.now()-7200000),scheduledEndAt:new Date(Date.now()-3600000)});
  await assert.rejects(call('completeLesson','other',{lessonId,reviewScore:4,feedback:''}),{code:'permission-denied'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:'good'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:'good'});
  await call('respondLessonCompletion','student',{lessonId,decision:'confirm'});
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
test('bulk scheduling: idempotent retries preserve bookings and cannot overwrite edited slots', async () => {
  const start = Date.now() + 1000 * 86400000;
  const slots = [0, 1].map(i => ({startAtMillis: start + i * 3600000, endAtMillis: start + (i + 1) * 3600000}));
  await assert.rejects(call('saveAvailabilitySlots', 'student', {slots}), {code: 'permission-denied'});
  await assert.rejects(call('saveAvailabilitySlots', 'coach', {coachUid: 'other', slots}), {code: 'permission-denied'});
  await assert.rejects(call('saveAvailabilitySlots', 'coach', {slots: [slots[0], slots[0]]}), {code: 'already-exists'});
  const result = await call('saveAvailabilitySlots', 'coach', {coachUid: 'coach', slots});
  assert.deepEqual(await call('saveAvailabilitySlots', 'coach', {slots}), result);
  const path = 'instructors/coach/availability';
  assert.equal((await getDocs(collection(db('coach'), path))).size, 2);
  const {lessonId} = await call('requestLessonWithSlot', 'student', {instructorId: 'coach', slotId: result.slotIds[0]});
  assert.deepEqual(await call('saveAvailabilitySlots', 'coach', {slots}), result);
  const booked = (await getDoc(doc(db('coach'), `${path}/${result.slotIds[0]}`))).data();
  assert.equal(booked.status, 'booked');
  assert.equal(booked.lessonId, lessonId);
  await assert.rejects(call('saveAvailabilitySlots', 'coach', {slots: [{startAtMillis: start + 1000, endAtMillis: start + 3600000}]}), {code: 'already-exists'});
  const moved = {startAtMillis: start + 3 * 3600000, endAtMillis: start + 4 * 3600000};
  await call('saveAvailabilitySlot', 'coach', {slotId: result.slotIds[1], ...moved});
  await assert.rejects(call('saveAvailabilitySlots', 'coach', {slots: [slots[1]]}), {code: 'failed-precondition'});
  const edited = (await getDoc(doc(db('coach'), `${path}/${result.slotIds[1]}`))).data();
  assert.equal(edited.startAt.toMillis(), moved.startAtMillis);
  assert.equal((await getDocs(collection(db('coach'), path))).size, 2);
});

test('notification inbox: owner-only read state, no forged notices or cross-account backfill', async () => {
  const data = {kind:'chat',title:'private',body:'message preview',targetType:'chat',targetId:'coach_student',createdAt:new Date(),readAt:null};
  await seed('users/student/notifications/notice',data);
  await assertSucceeds(getDocs(collection(db('student'),'users/student/notifications')));
  for (const uid of ['coach','other','admin','suspended','incomplete',null]) {
    await assertFails(getDoc(doc(db(uid),'users/student/notifications/notice')));
    await assertFails(getDocs(collection(db(uid),'users/student/notifications')));
  }
  const own = doc(db('student'),'users/student/notifications/notice');
  await assertFails(setDoc(doc(db('student'),'users/student/notifications/forged'),data));
  await assertFails(updateDoc(own,{title:'forged',readAt:serverTimestamp()}));
  await assertFails(updateDoc(own,{readAt:new Date(0)}));
  await assertFails(deleteDoc(own));
  await assertSucceeds(updateDoc(own,{readAt:serverTimestamp()}));
  for (const uid of [null,'incomplete','suspended','missing']) {
    await assert.rejects(call('syncMyNotifications',uid,{}),{code:uid ? 'permission-denied':'unauthenticated'});
  }
  await assert.rejects(call('syncMyNotifications','student',{uid:'coach'}),{code:'invalid-argument'});
});

test('notification events: participants only, unread preservation and idempotent history sync', async () => {
  const {Timestamp} = createRequire(new URL('../functions/package.json', import.meta.url))('firebase-admin/firestore');
  const notices = require('../functions/lib/src/notifications.js');
  const at = Timestamp.now();
  const data = {...lesson,createdAt:at,updatedAt:at};
  await seed('lesson_requests/event',{...lesson,createdAt:new Date(),updatedAt:new Date()});
  await notices.notifyLesson('event',data);
  const studentNotices = () => getDocs(collection(db('student'),'users/student/notifications'));
  assert.equal((await studentNotices()).size,1);
  assert.equal((await getDocs(collection(db('coach'),'users/coach/notifications'))).size,1);
  assert.equal((await getDocs(collection(db('other'),'users/other/notifications'))).size,0);
  const first = (await studentNotices()).docs[0];
  await assertSucceeds(updateDoc(first.ref,{readAt:serverTimestamp()}));
  await notices.notifyLesson('event',data);
  assert.ok((await getDoc(first.ref)).data().readAt);
  await notices.notifyLesson('event',{...data,status:'completed',attendanceBadge:{instructorUid:'coach',instructorName:'coach',signatureMove:'패스',verifiedBy:'coach'},signatureMove:'패스'},data);
  const kinds = (await studentNotices()).docs.map(d=>d.data().kind);
  assert.ok(kinds.includes('badge'));assert.equal(kinds.filter(k=>k==='lesson').length,2);
  await seed('chat_rooms/coach_student/messages/message',{senderId:'coach',text:'코치 피드백',createdAt:new Date()});
  await notices.notifyChat('coach_student','message',{senderId:'coach',text:'코치 피드백',createdAt:at});
  await notices.notifyChat('coach_student','message',{senderId:'coach',text:'코치 피드백',createdAt:at});
  assert.equal((await studentNotices()).docs.filter(d=>d.data().kind==='chat').length,1);
  assert.equal((await getDocs(collection(db('coach'),'users/coach/notifications'))).docs.filter(d=>d.data().kind==='chat').length,0);
  await notices.notifyChat('coach_student','forged',{senderId:'other',text:'forged',createdAt:at});
  assert.equal((await studentNotices()).docs.filter(d=>d.data().body==='forged').length,0);
  await notices.notifyFeedback('event','video',{uploaderUid:'coach',uploaderName:'coach',description:'자세 피드백',createdAt:at});
  assert.equal((await studentNotices()).docs.filter(d=>d.data().kind==='feedback').length,1);
  const before = (await studentNotices()).size;
  await call('syncMyNotifications','student',{category:'lessons'});
  const after = (await studentNotices()).size;
  await call('syncMyNotifications','student',{category:'lessons'});
  assert.equal((await studentNotices()).size,after);
  assert.ok(after>=before);
  await notices.notifyCoach('coach',{status:'pending',name:'applicant',submittedAt:at});
  const admins = await getDocs(collection(db('admin'),'users/admin/notifications'));
  assert.equal(admins.size,1);assert.equal(admins.docs[0].data().targetType,'admin');
  assert.equal((await getDocs(collection(db('other'),'users/other/notifications'))).size,0);
  await seed('users/student',{...profile('student'),accountStatus:'suspended'});
  await notices.notifyChat('coach_student','suspended',{senderId:'coach',text:'blocked',createdAt:at});
  await env.withSecurityRulesDisabled(async c => {
    assert.equal((await getDocs(collection(c.firestore(),'users/student/notifications'))).docs.filter(d=>d.data().body==='blocked').length,0);
  });
});

test('new coach applications can only be created during coach signup', async () => {
  await seed('signature_badges/kick',{name:'kick',colorIndex:7});
  const submission = uid => ({uid,userId:uid,name:'applicant',sport:'축구',career:'experience',signatureMove:'kick',signatureBadgeId:'kick',signatureBadgeColorIndex:7,status:'pending',rating:'0.0',createdAt:serverTimestamp(),submittedAt:serverTimestamp(),updatedAt:serverTimestamp()});
  await assertFails(setDoc(doc(db('student'),'instructors/student'),submission('student')));
  await seed('users/other',profile('other',{profileCompleted:false,requestedRole:'student'}));
  await assertFails(setDoc(doc(db('other'),'instructors/other'),submission('other')));
  await seed('users/other',profile('other',{profileCompleted:false,requestedRole:'coach'}));
  await assertSucceeds(setDoc(doc(db('other'),'instructors/other'),submission('other')));
});

test('registered 24-hour availability supports repeated edits without duplicates and keeps booking locks', async () => {
  const start=Date.now()+10*86400000;
  const {slotIds}=await call('saveAvailabilitySlots','coach',{slots:[{startAtMillis:start,endAtMillis:start+86400000}]});
  const slotId=slotIds[0];
  const ranges=[{startAtMillis:start,endAtMillis:start+86400000},
    {startAtMillis:start+86400000,endAtMillis:start+2*86400000},
    {startAtMillis:start+3*86400000,endAtMillis:start+3*86400000+3600000}];
  for(const range of ranges){
    const result=await call('saveAvailabilitySlot','coach',{slotId,...range});assert.equal(result.slotId,slotId);
  }
  const path='instructors/coach/availability';
  const own=await getDocs(collection(db('coach'),path));assert.equal(own.size,1);
  assert.equal(own.docs[0].data().startAt.toMillis(),ranges[2].startAtMillis);
  await call('requestLessonWithSlot','student',{instructorId:'coach',slotId});
  await assert.rejects(call('saveAvailabilitySlot','coach',{slotId,...ranges[0]}),{code:'failed-precondition'});
  assert.equal((await getDoc(doc(db('coach'),`${path}/${slotId}`))).data().status,'booked');
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
  await call('respondScheduleChange','student',{lessonId,decision:'approve'});
  const history=await getDocs(collection(db('student'),`lesson_requests/${lessonId}/schedule_changes`));
  assert.equal(history.size,1); assert.ok(history.docs[0].data().newStartAt);
  const third=await call('saveAvailabilitySlot','coach',{startAtMillis:end+3600000,endAtMillis:end+7200000});
  await call('rescheduleLesson','student',{lessonId,slotId:third.slotId});
  await call('respondScheduleChange','coach',{lessonId,decision:'approve'});
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
  assert.equal((await getDoc(doc(db('admin'),'feed_videos/video'))).exists(),false);
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
  await call('acceptLesson','coach',{lessonId});
  await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),`lesson_requests/${lessonId}`),{scheduledStartAt:new Date(Date.now()-7200000),scheduledEndAt:new Date(Date.now()-3600000)}));
  await env.withSecurityRulesDisabled(c => deleteDoc(doc(c.firestore(),'instructors/coach')));
  await assert.rejects(call('completeLesson','coach',{lessonId,reviewScore:4,feedback:''}),{code:'permission-denied'});
  await seed('instructors/coach',{uid:'coach',userId:'coach',name:'coach',sport:lesson.sport,status:'approved'});
  await call('completeLesson','coach',{lessonId,reviewScore:4,feedback:''});
  await call('respondLessonCompletion','student',{lessonId,decision:'confirm'});
  const completed=(await getDoc(doc(db('student'),`lesson_requests/${lessonId}`))).data();
  assert.equal(completed.attendanceBadge.signatureMove,'kick');
  const second='second'; await seed(`lesson_requests/${second}`,{studentUid:'student',instructorUid:'coach',participantIds:['coach','student'],status:'accepted',signatureMove:'kick',paymentRequired:false,scheduledStartAt:new Date(Date.now()-7200000),scheduledEndAt:new Date(Date.now()-3600000)});
  await call('completeLesson','coach',{lessonId:second,reviewScore:4,feedback:''});
  await call('respondLessonCompletion','student',{lessonId:second,decision:'confirm'});
  const student=(await getDoc(doc(db('student'),'users/student'))).data();
  assert.equal(student.lessonCount,2); assert.deepEqual(student.reviewScores,[4,4]);
});

test('legacy client booking/acceptance batches cannot bypass calendar validation', async () => {
  const d=db('student'), r=doc(d,'lesson_requests/client'), pair=doc(d,'active_lesson_requests/coach_student');
  const data={...lesson,instructorId:'coach',status:'pending',signatureMove:'kick',isInstructorInitiated:false,createdAt:serverTimestamp()};
  await assertFails(setDoc(r,data));
  for(const patch of [{studentName:'forged'},{instructorName:'forged'},{signatureMove:'forged'},{participantIds:['student','other']}]) {
    const batch=writeBatch(d); batch.set(r,{...data,...patch}); batch.set(pair,{requestId:'client',participantIds:['coach','student']});
    await assertFails(batch.commit());
  }
  const create=writeBatch(d); create.set(r,data); create.set(pair,{requestId:'client',participantIds:['coach','student']});
  await assertFails(create.commit());
  await env.withSecurityRulesDisabled(c=>deleteDoc(doc(c.firestore(),'chat_rooms/coach_student')));
  const coachDb=db('coach'), coachRef=doc(coachDb,'lesson_requests/client');
  await assertFails(updateDoc(coachRef,{status:'accepted',updatedAt:serverTimestamp()}));
  const accept=writeBatch(coachDb); accept.update(coachRef,{status:'accepted',updatedAt:serverTimestamp()});
  accept.set(doc(coachDb,'chat_rooms/coach_student'),{participantIds:['coach','student'],studentUid:'student',studentName:'student',coachUid:'coach',coachName:'coach'});
  await assertFails(accept.commit());
  await assertFails(updateDoc(coachRef,{status:'rejected',updatedAt:serverTimestamp()}));
});

test('legacy completion batches cannot bypass student confirmation', async () => {
  await seed('active_lesson_requests/coach_student',{requestId:'lesson',participantIds:['coach','student']});
  const d=db('coach'), r=doc(d,'lesson_requests/lesson'), student=doc(d,'users/student');
  const completion={status:'completed',reviewScore:4,reviewFeedback:'good',attendanceBadge:{instructorUid:'coach',instructorName:'coach',sport:lesson.sport,signatureMove:'kick',awardedAt:serverTimestamp(),verifiedBy:'coach'},completedAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(updateDoc(r,completion));
  await assertFails(updateDoc(student,{lastCompletedLessonId:'lesson',lessonCount:1,reviewScores:[4],teacherMatchCount:0}));
  const batch=writeBatch(d); batch.update(r,completion); batch.update(student,{lastCompletedLessonId:'lesson',lessonCount:1,reviewScores:[4],teacherMatchCount:0}); batch.delete(doc(d,'active_lesson_requests/coach_student'));
  await assertFails(batch.commit());
  assert.equal((await getDoc(doc(db('student'),'users/student'))).data().lessonCount,0);
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

test('legacy report records remain readable by admins and server enforces original text limits', async () => {
  const d=db('student');
  const legacy={reporterUid:'student',reportedUid:'coach',reportedUserName:'coach',reason:'r'.repeat(500),details:'d'.repeat(5000),timestamp:serverTimestamp(),status:'pending'};
  await assertFails(setDoc(doc(d,'reports/legacy'),legacy));
  await assertFails(setDoc(doc(d,'reports/spoof'),{...legacy,reporterUid:'coach'}));
  const modern={reporterId:'student',reporterEmail:'student@example.test',reportedUserId:'coach',reportedUserName:'coach',reason:'r'.repeat(500),detail:'d'.repeat(5000),sanctionType:'OTHER',status:'PENDING',createdAt:serverTimestamp()};
  await assertFails(setDoc(doc(d,'reports/modern'),modern));
  await assertFails(setDoc(doc(d,'reports/email-spoof'),{...modern,reporterEmail:'coach@example.test'}));
  await assertFails(setDoc(doc(d,'reports/long'),{...legacy,details:'d'.repeat(5001)}));
  await seed('reports/legacy', {...legacy, timestamp:new Date()});
  await seed('reports/modern', {...modern, createdAt:new Date()});
  for (const id of ['legacy','modern']) {
    await assertSucceeds(getDoc(doc(db('admin'),`reports/${id}`)));
    await assertFails(getDoc(doc(d,`reports/${id}`)));
  }
  const response=await call('submitReport','student',{targetType:'user',targetId:'coach',reason:'r'.repeat(500),details:'d'.repeat(5000),requestId:'text-boundary'});
  assert.ok(response.reportId);
  await assert.rejects(call('submitReport','student',{targetType:'user',targetId:'coach',reason:'r',details:'d'.repeat(5001),requestId:'too-long'}),{code:'invalid-argument'});
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
