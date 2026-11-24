import {createHash} from 'node:crypto';
import {getFirestore, FieldValue, Timestamp} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {defineSecret} from 'firebase-functions/params';
import webpush from 'web-push';
import {authenticatedInput,activeMember,areBlocked} from './platform_access';
import {documentId} from './domain';

const options={region:'asia-northeast3',maxInstances:2};
const privateKey=defineSecret('WEB_PUSH_PRIVATE_KEY');
const db=()=>getFirestore(), stamp=()=>FieldValue.serverTimestamp();
const digest=(s:string)=>createHash('sha256').update(s).digest('hex');
type Data=Record<string,any>;
export function validatedPushDevice(provider:unknown,value:unknown): {key:string;provider:string;subscription?:Data;token?:string} {
  if(provider==='fcm'){
    if(typeof value!=='string'||value.length<20||value.length>4096||!/^[A-Za-z0-9:_-]+$/.test(value))throw new HttpsError('invalid-argument','기기 토큰을 확인해 주세요.');
    return {key:digest('fcm:'+value),provider:'fcm',token:value};
  }
  const s=value as Data;
  if(provider!=='web'||!s||typeof s.endpoint!=='string'||s.endpoint.length>2048)throw new HttpsError('invalid-argument','브라우저 알림 정보를 확인해 주세요.');
  let u:URL;try{u=new URL(s.endpoint);}catch{throw new HttpsError('invalid-argument','알림 주소가 올바르지 않습니다.');}
  const h=u.hostname;
  if(u.protocol!=='https:'||u.username||u.password||(u.port&&u.port!=='443')||!(h==='fcm.googleapis.com'||h==='updates.push.services.mozilla.com'||h==='push.services.mozilla.com'||h==='web.push.apple.com'||h.endsWith('.notify.windows.com')))throw new HttpsError('invalid-argument','지원하는 브라우저 알림 주소가 아닙니다.');
  if(typeof s.keys?.auth!=='string'||typeof s.keys?.p256dh!=='string'||!/^[-_a-zA-Z0-9]+=*$/.test(s.keys.auth)||!/^[-_a-zA-Z0-9]+=*$/.test(s.keys.p256dh)||Buffer.from(s.keys.auth,'base64url').length!==16||Buffer.from(s.keys.p256dh,'base64url').length!==65)throw new HttpsError('invalid-argument','알림 암호화 키를 확인해 주세요.');
  return {key:digest('web:'+s.endpoint),provider:'web',subscription:{endpoint:s.endpoint,keys:{auth:s.keys.auth,p256dh:s.keys.p256dh}}};
}
export const getPushConfiguration=onCall(options,async r=>{
  const {uid}=authenticatedInput(r,[]);
  return db().runTransaction(async tx=>{
    const u=await activeMember(tx,uid),c=(await tx.get(db().doc('app_config/push'))).data();
    return {publicKey:c?.publicKey??null,enabled:u.pushEnabled===true,previews:u.pushPreviews!==false};
  });
});
export const registerPushDevice=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['provider','subscription','token']);
  const device=validatedPushDevice(data.provider,data.provider==='web'?data.subscription:data.token);
  await db().runTransaction(async tx=>{
    await activeMember(tx,uid);
    const devices=await tx.get(db().collection('push_devices').where('uid','==',uid));
    const ref=db().doc(`push_devices/${device.key}`);
    await tx.get(ref); // Serializes transfers of one browser/device across accounts.
    const oldest=devices.docs.filter(d=>d.id!==device.key).sort((a,b)=>(a.data().updatedAt?.toMillis()??0)-(b.data().updatedAt?.toMillis()??0));
    for(const d of oldest.slice(0,Math.max(0,oldest.length-9)))tx.delete(d.ref);
    tx.set(ref,{...device,uid,updatedAt:stamp()});
    tx.update(db().doc(`users/${uid}`),{pushEnabled:true});
  });
  return {deviceId:device.key};
});
export const unregisterPushDevice=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['deviceId']);
  const ref=db().doc(`push_devices/${documentId(data.deviceId,'deviceId')}`);
  await db().runTransaction(async tx=>{const d=(await tx.get(ref)).data();if(d?.uid===uid)tx.delete(ref);});
  return {removed:true};
});
export const setPushPreference=onCall(options,async r=>{
  const {uid,data}=authenticatedInput(r,['enabled','previews']);
  if((data.enabled!==undefined&&typeof data.enabled!=='boolean')||(data.previews!==undefined&&typeof data.previews!=='boolean')||!Object.keys(data).length)throw new HttpsError('invalid-argument','알림 설정을 확인해 주세요.');
  await db().runTransaction(async tx=>{
    await activeMember(tx,uid);
    const devices=data.enabled===false?await tx.get(db().collection('push_devices').where('uid','==',uid)):null;
    tx.update(db().doc(`users/${uid}`),{...(data.enabled!==undefined?{pushEnabled:data.enabled}:{}),...(data.previews!==undefined?{pushPreviews:data.previews}:{})});
    for(const doc of devices?.docs??[])tx.delete(doc.ref);
  });
  return {saved:true};
});

type Transports={web:(subscription:Data,payload:Data,publicKey:string)=>Promise<void>;fcm:(token:string,payload:Data)=>Promise<void>};
const transports:Transports={
  web:async(subscription,payload,publicKey)=>{await webpush.sendNotification(subscription as webpush.PushSubscription,JSON.stringify(payload),{TTL:300,urgency:'normal',vapidDetails:{subject:'https://onlyonepoint-lesson.web.app',publicKey,privateKey:privateKey.value()}});},
  fcm:async(token,p)=>{await getMessaging().send({token,notification:{title:p.title,body:p.body},data:{ownerUid:p.ownerUid,notificationId:p.notificationId},android:{ttl:300000,notification:{tag:p.notificationId,channelId:'onepoint_channel'}},apns:{headers:{'apns-collapse-id':p.notificationId},payload:{aps:{sound:'default'}}}});}
};
export async function deliverPush(uid:string,id:string,send:Transports=transports){
  const noticeRef=db().doc(`users/${uid}/notifications/${id}`),deliveryRef=db().doc(`push_deliveries/${uid}_${id}`);
  const batch=await db().runTransaction(async tx=>{
    const notice=(await tx.get(noticeRef)).data(),user=(await tx.get(db().doc(`users/${uid}`))).data();
    const delivery=(await tx.get(deliveryRef)).data();
    const config=(await tx.get(db().doc('app_config/push'))).data();
    if(!notice||notice.pushEligible!==true||notice.readAt||user?.pushEnabled!==true||(user.accountStatus??'active')!=='active'||user.profileCompleted!==true||!(notice.createdAt instanceof Timestamp)||notice.createdAt.toMillis()<Date.now()-300000||delivery?.status==='done')return null;
    if(delivery?.leaseUntil?.toMillis()>Date.now())throw new HttpsError('aborted','알림 전송이 진행 중입니다.');
    const devices=await tx.get(db().collection('push_devices').where('uid','==',uid));
    const completed:string[]=delivery?.completed??[];
    if(['chat','feed'].includes(notice.kind)&&typeof notice.sourceUid==='string'&&await areBlocked(tx,uid,notice.sourceUid))return null;
    tx.set(deliveryRef,{status:'sending',completed,leaseUntil:Timestamp.fromMillis(Date.now()+60000),updatedAt:stamp()});
    return {notice,user,devices:devices.docs.filter(d=>!completed.includes(d.id)).map(d=>({id:d.id,...d.data()} as Data)),completed,publicKey:config?.publicKey};
  });
  if(!batch)return;
  let retry=false;
  const completed=[...batch.completed];
  for(const d of batch.devices){
    const current=(await db().doc(`push_devices/${d.id}`).get()).data();
    if(current?.uid!==uid){completed.push(d.id);continue;}
    const payload={ownerUid:uid,notificationId:id,title:String(batch.notice.title??'onepoint'),body:batch.user.pushPreviews===false?'새 알림이 도착했습니다.':String(batch.notice.body??'')};
    try{
      if(d.provider==='web'){
        if(typeof batch.publicKey!=='string')throw Error('Web push public key missing');
        await send.web(d.subscription,payload,batch.publicKey);
      }else await send.fcm(d.token,payload);
      completed.push(d.id);
    }catch(error){
      const e=error as {statusCode?:number;code?:string};
      if([404,410].includes(e.statusCode??0)||['messaging/invalid-registration-token','messaging/registration-token-not-registered'].includes(e.code??'')){
        await db().runTransaction(async tx=>{const ref=db().doc(`push_devices/${d.id}`);if((await tx.get(ref)).data()?.uid===uid)tx.delete(ref);});
        completed.push(d.id);
      }else retry=true;
    }
  }
  await deliveryRef.set({status:retry?'retry':'done',completed,leaseUntil:Timestamp.fromMillis(0),updatedAt:stamp()});
  if(retry)throw new HttpsError('unavailable','일부 기기 알림 전송을 재시도합니다.');
}
export const sendNotificationPush=onDocumentCreated({...options,retry:true,secrets:[privateKey],document:'users/{uid}/notifications/{id}'},e=>deliverPush(e.params.uid,e.params.id));
