import assert from "node:assert/strict";
import {test} from "node:test";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {cancelPayment, confirmPayment, getPaymentStatus, preparePayment, object} from "../src/index";
import {requestId} from "../src/domain";

function request(uid?: string, data: unknown = {}): CallableRequest {
  return {data, auth: uid ? {uid, token: {}} : undefined} as CallableRequest;
}
const errorCode = (code: string) => (error: unknown) => error instanceof HttpsError && error.code === code;

test("all callable endpoints reject missing authentication before accessing Firestore", async () => {
  for (const callable of [preparePayment, getPaymentStatus, confirmPayment, cancelPayment]) {
    await assert.rejects(callable.run(request()), errorCode("unauthenticated"));
  }
});

test("approval and refund exports reject forged state/amount payloads", async () => {
  for (const callable of [confirmPayment, cancelPayment]) {
    assert.throws(() => object({paymentStatus: "paid", amount: 100}, callable === confirmPayment ? ["paymentId", "paymentKey"] : ["paymentId", "refundId", "amount", "reason"]), errorCode("invalid-argument"));
  }
});

test("preparation callable rejects a supplied amount before any database access", async () => {
  assert.throws(() => requestId({lessonId: "lesson", amount: 100}, "lessonId"), errorCode("invalid-argument"));
});

test("status callable rejects unsupported request shape before database access", async () => {
  assert.throws(() => requestId({paymentId: "payments/id"}, "paymentId"), errorCode("invalid-argument"));
});
