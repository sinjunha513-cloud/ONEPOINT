import assert from 'node:assert/strict';
import {test} from 'node:test';
import {HttpsError} from 'firebase-functions/v2/https';
import {documentId,signatureBadgeId} from '../src/domain';

test('badge lookup accepts normalized Korean, jamo, Latin and numeric catalog IDs',()=>{
  for(const id of ['라크로케타','패스마스터','ㄱㅏ','kick','kick123','123','가'.repeat(20)]) {
    assert.equal(signatureBadgeId(id),id);
  }
});
test('badge IDs reject paths and invalid catalog words without relaxing other document IDs',()=>{
  for(const id of [undefined,null,1,'','..','../users/coach','a/b','가/나','가 나','Kick','kick_badge','가'.repeat(21),'패스\n']) {
    assert.throws(()=>signatureBadgeId(id),e=>e instanceof HttpsError&&e.code==='invalid-argument');
  }
  assert.throws(()=>documentId('라크로케타','lessonId'),e=>e instanceof HttpsError&&e.code==='invalid-argument');
  assert.equal(documentId('lesson_123','lessonId'),'lesson_123');
});
