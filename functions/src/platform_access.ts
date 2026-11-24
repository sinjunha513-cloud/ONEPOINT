import {getFirestore, Transaction} from 'firebase-admin/firestore';
import {CallableRequest, HttpsError} from 'firebase-functions/v2/https';

export function authenticatedInput(r: CallableRequest, keys: string[]) {
  if (!r.auth) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  if (!r.data || typeof r.data !== 'object' || Array.isArray(r.data) || Object.keys(r.data).some(k => !keys.includes(k))) throw new HttpsError('invalid-argument', '요청 항목을 확인해 주세요.');
  return {uid:r.auth.uid, data:r.data as Record<string, unknown>};
}
export async function activeMember(tx: Transaction, uid: string, complete = true) {
  const user=(await tx.get(getFirestore().collection('users').doc(uid))).data();
  if (!user || (user.accountStatus??'active')!=='active' || (complete && user.profileCompleted!==true)) throw new HttpsError('permission-denied', '활성 계정으로 로그인해 주세요.');
  return user;
}
export async function assertNotBlocked(tx: Transaction, a: string, b: string) {
  if(await areBlocked(tx,a,b))throw new HttpsError('permission-denied','현재 이 회원과 새 활동을 진행할 수 없습니다.');
}
export async function areBlocked(tx:Transaction,a:string,b:string){
  const db=getFirestore();
  const docs=await tx.getAll(db.doc(`user_blocks/${a}/members/${b}`),db.doc(`user_blocks/${b}/members/${a}`));
  return docs.some(d=>d.exists);
}
export function requiredReason(value: unknown, max=500) {
  if(typeof value!=='string'||!value.trim()||value.trim().length>max)throw new HttpsError('invalid-argument',`사유를 1~${max}자로 입력해 주세요.`);
  return value.trim();
}
