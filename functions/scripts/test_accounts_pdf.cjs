const assert=require('node:assert/strict');
const {initializeApp}=require('firebase-admin/app');const {getAuth}=require('firebase-admin/auth');const {getFirestore}=require('firebase-admin/firestore');const {getStorage}=require('firebase-admin/storage');const {PDFDocument}=require('pdf-lib');
if(process.env.GCLOUD_PROJECT!=='demo-onepoint-payments'||!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST||!process.env.STORAGE_EMULATOR_HOST)throw new Error('Isolated emulators only');
initializeApp({projectId:'demo-onepoint-payments',storageBucket:'demo-onepoint-payments.appspot.com'});
const db=getFirestore(),auth=getAuth(),tokens={},suffix=Date.now().toString(36),ids={admin:`manage-admin-${suffix}`,coach:`manage-coach-${suffix}`,student:`manage-student-${suffix}`};
async function call(role,name,data){const response=await fetch(`http://127.0.0.1:5101/demo-onepoint-payments/asia-northeast3/${name}`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${tokens[role]}`},body:JSON.stringify({data})});const b=await response.json();if(b.error){const e=new Error(b.error.message);e.code=b.error.status;throw e;}return b.result;}
async function login(role){const r=await fetch('http://127.0.0.1:9198/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`${ids[role]}@demo.test`,password:'demo-account-tests',returnSecureToken:true})});return r.json();}
async function main(){
 for(const role of Object.keys(ids)){await auth.createUser({uid:ids[role],email:`${ids[role]}@demo.test`,password:'demo-account-tests'});await db.collection('users').doc(ids[role]).set({role,name:role,profileCompleted:true,accountStatus:'active'});tokens[role]=(await login(role)).idToken;}
 await db.collection('instructors').doc(ids.coach).set({uid:ids.coach,userId:ids.coach,name:'test coach',sport:'테니스',career:'career',status:'approved'});
 await assert.rejects(call('student','adminManageAccount',{uid:ids.coach,action:'delete',reason:'forged'}),e=>e.code==='PERMISSION_DENIED');
 await assert.rejects(call('admin','adminManageAccount',{uid:ids.admin,action:'delete',reason:'self'}),e=>e.code==='FAILED_PRECONDITION');console.log('PASS unauthorized account deletion and self-admin deletion denied');
 await call('admin','adminManageAccount',{uid:ids.coach,action:'suspend',reason:'test suspension'});
 assert.equal((await auth.getUser(ids.coach)).disabled,true);assert.equal((await db.collection('instructors').doc(ids.coach).get()).data().status,'suspended');
 await assert.rejects(call('coach','getPaymentSummary',{}),e=>e.code==='PERMISSION_DENIED');assert.ok((await login('coach')).error);console.log('PASS suspension disables login, old callable token and public coach profile');
 await call('admin','adminManageAccount',{uid:ids.coach,action:'restore',reason:'test restore'});assert.equal((await auth.getUser(ids.coach)).disabled,false);assert.equal((await db.collection('instructors').doc(ids.coach).get()).data().status,'approved');console.log('PASS restoration re-enables Auth and previous approved profile');
 await db.collection('instructors').doc(ids.coach).update({status:'pending'});
 await call('admin','adminManageAccount',{uid:ids.coach,action:'suspend',reason:'pending profile'});
 await call('admin','adminManageAccount',{uid:ids.coach,action:'restore',reason:'restore pending profile'});
 assert.equal((await db.collection('instructors').doc(ids.coach).get()).data().status,'pending');console.log('PASS restoration never bypasses a pending coach review');
 const pdf=await PDFDocument.create();pdf.addPage().drawText('ONEPOINT career PDF test');const bytes=await pdf.save(),id=`pdf_${suffix}`;
 const path=`coach_documents/${ids.coach}/${id}.pdf`;await getStorage().bucket().file(path).save(Buffer.from(bytes),{resumable:false,metadata:{contentType:'application/pdf'}});
 const verified=await call('coach','validateCareerPdf',{fileId:id,fileName:'career.pdf'});assert.equal(verified.fileId,id);
 assert.equal((await db.collection('coach_document_uploads').doc(ids.coach).collection('files').doc(id).get()).data().verified,true);console.log('PASS real PDF format verified and private ownership recorded');
 const invalid=`bad_${suffix}`;await getStorage().bucket().file(`coach_documents/${ids.coach}/${invalid}.pdf`).save(Buffer.from('not a PDF'),{resumable:false,metadata:{contentType:'application/pdf'}});
 await assert.rejects(call('coach','validateCareerPdf',{fileId:invalid,fileName:'fake.pdf'}),e=>e.code==='INVALID_ARGUMENT');console.log('PASS disguised non-PDF rejected');
 await call('admin','adminManageAccount',{uid:ids.coach,action:'delete',reason:'test deletion'});
 await assert.rejects(auth.getUser(ids.coach),e=>e.code==='auth/user-not-found');assert.equal((await db.collection('users').doc(ids.coach).get()).data().accountStatus,'deleted');assert.equal((await db.collection('instructors').doc(ids.coach).get()).exists,false);
 assert.equal((await getStorage().bucket().file(path).exists())[0],false);console.log('PASS permanent Auth deletion, anonymized profile, coach removal and PDF cleanup');
 console.log('Account/PDF integration tests passed. No production users modified.');
}
main().catch(e=>{console.error('FAIL',e.code||'',e.message);process.exitCode=1;});
