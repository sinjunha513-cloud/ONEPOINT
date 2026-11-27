type Data=Record<string,any>;
export function publicFeedData(source:Data,user:Data){
  const keys=source.sourceType==='lesson_feedback'
    ?['userId','title','description','createdAt','likes']
    :['userId','title','description','storagePath','createdAt','likes'];
  return {...Object.fromEntries(keys.filter(k=>source[k]!==undefined).map(k=>[k,source[k]])),
    userName:user.name??'회원',videoUrl:source.sourceType==='lesson_feedback'?'':source.storagePath??source.videoUrl,
    ...(source.sourceType==='lesson_feedback'?{contentType:'feedback'}:{})};
}
export function isPublicFeed(source:Data|undefined,user:Data|null|undefined){
  return !!source&&!source.deleting&&source.visibility!=='private'&&source.moderationStatus!=='hidden'
    &&!!user&&user.profileCompleted===true&&(user.accountStatus??'active')==='active';
}
