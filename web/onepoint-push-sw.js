'use strict';
const STATE='onepoint-push-state-v1';
const ownerRequest=new Request(new URL('/onepoint-push-owner',self.location.origin));
async function owner(){return (await (await caches.open(STATE)).match(ownerRequest))?.text()??'';}
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('message',event=>{
  if(event.data?.type!=='ONEPOINT_SESSION')return;
  event.waitUntil((async()=>{
    try{
      const cache=await caches.open(STATE),current=await owner();
      if(event.data.uid)await cache.put(ownerRequest,new Response(event.data.uid));
      const cleared=!event.data.uid&&(!event.data.expectedUid||event.data.expectedUid===current);
      if(cleared)await cache.delete(ownerRequest);
      event.ports[0]?.postMessage({ok:true,cleared});
    }catch{event.ports[0]?.postMessage({ok:false});}
  })());
});
self.addEventListener('push',event=>event.waitUntil((async()=>{
  let data;try{data=event.data?.json();}catch{return;}
  let current;try{current=await owner();}catch{return;}
  if(!data||!data.ownerUid||data.ownerUid!==current||!/^[-_a-zA-Z0-9]{1,128}$/.test(data.notificationId))return;
  await self.registration.showNotification(String(data.title||'onepoint'),{
    body:String(data.body||''),tag:data.notificationId,
    icon:'/icons/Icon-192.png',data:{ownerUid:data.ownerUid,notificationId:data.notificationId}
  });
})()));
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    const data=event.notification.data;
    let current;try{current=await owner();}catch{return;}
    if(!data||data.ownerUid!==current)return;
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    const client=windows.find(c=>new URL(c.url).origin===self.location.origin);
    if(client){await client.focus();client.postMessage({type:'ONEPOINT_OPEN_NOTIFICATION',...data});}
    else{
      const url=new URL('/',self.location.origin);
      url.searchParams.set('notificationId',data.notificationId);url.searchParams.set('ownerUid',data.ownerUid);
      await self.clients.openWindow(url.toString());
    }
  })());
});
