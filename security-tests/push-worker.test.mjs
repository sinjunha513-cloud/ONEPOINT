import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('../web/onepoint-push-sw.js',import.meta.url),'utf8');
function worker({cacheUnavailable=false,windows=[]}={}) {
  const handlers=new Map(), stored=new Map(), shown=[], opened=[], sent=[];
  const self={location:{origin:'https://onepoint.test'},skipWaiting:async()=>{},
    addEventListener:(type,handler)=>handlers.set(type,handler),
    registration:{showNotification:async(title,options)=>shown.push({title,...options})},
    clients:{matchAll:async()=>windows,openWindow:async url=>opened.push(url)}};
  const caches={open:async()=>{
    if(cacheUnavailable)throw new Error('Cache API denied');
    return {match:async key=>stored.has(key.url)?new Response(stored.get(key.url)):undefined,
      put:async(key,response)=>stored.set(key.url,await response.text()),
      delete:async key=>stored.delete(key.url)};
  }};
  vm.runInNewContext(source,{self,caches,Request,Response,URL});
  async function dispatch(type,event){let pending;handlers.get(type)({...event,waitUntil:p=>{pending=p;}});await pending;}
  return {shown,opened,sent,
    bind:async(uid,expectedUid)=>{await dispatch('message',{data:{type:'ONEPOINT_SESSION',uid,expectedUid},ports:[{postMessage:m=>sent.push(m)}]});return sent.at(-1);},
    push:data=>dispatch('push',{data:{json:()=>data}}),
    click:data=>dispatch('notificationclick',{notification:{data,close(){}}})};
}
const notice={ownerUid:'member-a',notificationId:'lesson_notice-1',title:'레슨 알림',body:'새로운 레슨 요청이 있습니다.'};

test('push worker only previews valid notifications belonging to the current signed-in owner',async()=>{
  const w=worker();
  await w.push(notice);assert.equal(w.shown.length,0);
  await w.bind('member-a');
  await w.push({...notice,ownerUid:'someone-else'});
  await w.push({...notice,notificationId:'../private'});
  await w.push(null);assert.equal(w.shown.length,0);
  await w.push(notice);
  assert.equal(w.shown.length,1);assert.equal(w.shown[0].body,notice.body);
  assert.equal(w.shown[0].tag,notice.notificationId);
});
test('a delayed logout from a previous account cannot clear the newly signed-in account',async()=>{
  const w=worker();await w.bind('member-a');await w.bind('member-b');
  assert.equal((await w.bind('','member-a')).cleared,false);
  await w.push({...notice,ownerUid:'member-b'});assert.equal(w.shown.length,1);
  assert.equal((await w.bind('','member-b')).cleared,true);
  await w.push({...notice,ownerUid:'member-b'});assert.equal(w.shown.length,1);
  // Reload with no local Auth owner also clears a subscription from an older
  // signed-in page, even though the new page cannot recover its former UID.
  await w.bind('member-a');await w.bind('');
  await w.push(notice);assert.equal(w.shown.length,1);
});
test('denied browser storage suppresses previews without exposing private content',async()=>{
  const w=worker({cacheUnavailable:true});
  assert.equal((await w.bind('member-a')).ok,false);
  await w.push(notice);await w.click(notice);
  assert.equal(w.shown.length,0);assert.equal(w.opened.length,0);
});
test('notification taps focus a same-origin tab and only open the current owners notice',async()=>{
  const messages=[];let focusCount=0;
  const w=worker({windows:[{url:'https://attacker.test/',focus:async()=>{throw new Error('Wrong origin');}},
    {url:'https://onepoint.test/#/home',focus:async()=>focusCount++,postMessage:m=>messages.push(m)}]});
  await w.bind('member-a');await w.click({...notice,ownerUid:'member-b'});
  assert.equal(focusCount,0);
  await w.click(notice);assert.equal(focusCount,1);
  assert.equal(messages[0].notificationId,notice.notificationId);
  assert.equal(w.opened.length,0);
  const fresh=worker();await fresh.bind('member-a');await fresh.click(notice);
  const url=new URL(fresh.opened[0]);assert.equal(url.origin,'https://onepoint.test');
  assert.equal(url.searchParams.get('notificationId'),notice.notificationId);
  assert.equal(url.searchParams.get('ownerUid'),'member-a');
});
