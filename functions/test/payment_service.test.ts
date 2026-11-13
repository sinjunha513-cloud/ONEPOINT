import assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {assertLocalPreparation} from "../src/config";
import {calculateFees, paymentIdFor, requestId} from "../src/domain";
import {UnconnectedGateway} from "../src/gateway";
import {AccountDocument, InstructorDocument, LessonDocument, PaymentDocument} from "../src/models";
import {PaymentService} from "../src/payment_service";
import {PaymentStore, PaymentTransaction} from "../src/store";

class MemoryStore implements PaymentStore {
  lessons = new Map<string, LessonDocument>([["lesson", {status: "accepted", studentUid: "student",
    instructorUid: "coach", participantIds: ["coach", "student"], price: 50000, currency: "KRW"}]]);
  accounts = new Map<string, AccountDocument>([["student", {role: "student", profileCompleted: true}],
    ["coach", {role: "coach", profileCompleted: true}], ["admin", {role: "admin"}]]);
  instructors = new Map<string, InstructorDocument>([["coach", {status: "approved", uid: "coach", userId: "coach"}]]);
  payments = new Map<string, PaymentDocument>();
  failCommit = false;
  private queue: Promise<unknown> = Promise.resolve();
  now() { return Timestamp.fromMillis(1000); }
  async payment(id: string) { return this.payments.get(id); }
  async account(uid: string) { return this.accounts.get(uid); }
  transaction<T>(work: (transaction: PaymentTransaction) => Promise<T>): Promise<T> {
    const result = this.queue.then(async () => {
      const writes: (() => void)[] = [];
      const value = await work({
        lesson: async (id) => this.lessons.get(id),
        account: async (uid) => this.accounts.get(uid),
        instructor: async (uid) => this.instructors.get(uid),
        payment: async (id) => this.payments.get(id),
        createPayment: (id, payment) => { writes.push(() => this.payments.set(id, payment)); },
        linkLesson: (id, paymentId) => { writes.push(() => {
          this.lessons.set(id, {...this.lessons.get(id)!, paymentId, paymentStatus: "pending"});
        }); },
      });
      if (this.failCommit) throw new Error("commit unavailable");
      for (const write of writes) write();
      return value;
    });
    this.queue = result.catch(() => undefined);
    return result;
  }
}

const policy = {platformFeeBps: 1200};
function rejected(code: string) {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}
function fixture() { const store = new MemoryStore(); return {store, service: new PaymentService(store)}; }

test("request accepts only a lesson ID, never a caller's amount or status", () => {
  assert.equal(requestId({lessonId: "lesson"}, "lessonId"), "lesson");
  for (const data of [null, [], {lessonId: "../users/admin"}, {lessonId: "lesson", amount: 100},
    {lessonId: "lesson", paymentStatus: "paid"}, {lessonId: 10}]) {
    assert.throws(() => requestId(data, "lessonId"), rejected("invalid-argument"));
  }
});

test("unaccepted, rejected, cancelled, confirmed or completed lessons cannot be prepared", async () => {
  for (const status of ["pending", "rejected", "cancelled", "confirmed", "completed"] as const) {
    const {store, service} = fixture(); store.lessons.get("lesson")!.status = status;
    await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
    assert.equal(store.payments.size, 0);
  }
});

test("only the matching student can prepare payment", async () => {
  const {service, store} = fixture();
  for (const uid of ["coach", "admin", "stranger"]) {
    await assert.rejects(service.prepare(uid, "lesson", policy), rejected("permission-denied"));
  }
  assert.equal(store.payments.size, 0);
});

test("missing lesson is rejected", async () => {
  await assert.rejects(fixture().service.prepare("student", "missing", policy), rejected("not-found"));
});

test("no invented default price, fractional/invalid KRW price or currency is accepted", async () => {
  for (const price of [undefined, 0, -1, 0.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
    const {store, service} = fixture(); store.lessons.get("lesson")!.price = price;
    await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
  }
  const {store, service} = fixture(); delete store.lessons.get("lesson")!.currency;
  await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
});

test("50000 KRW snapshot has exact fees and only pending states", async () => {
  const {store, service} = fixture(); const payment = await service.prepare("student", "lesson", policy);
  assert.equal(payment.amount, 50000); assert.equal(payment.platformFee, 6000);
  assert.equal(payment.coachAmount, 44000); assert.equal(payment.paymentStatus, "pending");
  assert.equal(payment.payoutStatus, "pending"); assert.equal(payment.paidAt, null);
  assert.equal(store.lessons.get("lesson")!.status, "accepted");
  assert.equal(store.lessons.get("lesson")!.paymentId, payment.paymentId);
  assert.equal(payment.providerOrderId, paymentIdFor("lesson"));
});

test("concurrent preparation and retries create one payment and preserve its fee policy", async () => {
  const {store, service} = fixture();
  const results = await Promise.all(Array.from({length: 10}, () => service.prepare("student", "lesson", policy)));
  assert.equal(store.payments.size, 1); assert.equal(new Set(results.map((p) => p.paymentId)).size, 1);
  const retry = await service.prepare("student", "lesson", {platformFeeBps: 1000});
  assert.equal(retry.platformFeeBps, 1200); assert.equal(retry.platformFee, 6000);
});

test("paid payment cannot create a new payment", async () => {
  const {store, service} = fixture(); const payment = await service.prepare("student", "lesson", policy);
  store.payments.get(payment.paymentId)!.paymentStatus = "paid";
  store.lessons.get("lesson")!.paymentStatus = "paid";
  await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
  assert.equal(store.payments.size, 1);
});

test("price changes or broken references never overwrite a prepared payment", async () => {
  const {store, service} = fixture(); const payment = await service.prepare("student", "lesson", policy);
  store.lessons.get("lesson")!.price = 100;
  await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
  assert.equal(store.payments.get(payment.paymentId)!.amount, 50000);
  store.lessons.get("lesson")!.price = 50000; store.lessons.get("lesson")!.paymentId = "different";
  await assert.rejects(service.prepare("student", "lesson", policy), rejected("failed-precondition"));
});

test("transaction failure leaves payment and lesson reference unchanged", async () => {
  const {store, service} = fixture(); store.failCommit = true;
  await assert.rejects(service.prepare("student", "lesson", policy), /commit unavailable/);
  assert.equal(store.payments.size, 0); assert.equal(store.lessons.get("lesson")!.paymentId, undefined);
});

test("unapproved coach and incomplete student fail validation", async () => {
  const first = fixture(); first.store.instructors.get("coach")!.status = "pending";
  await assert.rejects(first.service.prepare("student", "lesson", policy), rejected("failed-precondition"));
  const second = fixture(); second.store.accounts.get("student")!.profileCompleted = false;
  await assert.rejects(second.service.prepare("student", "lesson", policy), rejected("failed-precondition"));
});

test("student/admin can read a safe payment view; unrelated users cannot", async () => {
  const {service} = fixture(); const payment = await service.prepare("student", "lesson", policy);
  for (const uid of ["student", "admin"]) {
    const view = await service.status(uid, payment.paymentId);
    assert.equal(view.amount, 50000); assert.equal(view.providerPaymentKey, undefined);
  }
  await assert.rejects(service.status("other-student", payment.paymentId), rejected("permission-denied"));
  await assert.rejects(service.status("other-coach", payment.paymentId), rejected("permission-denied"));
});

test("coach receives only settlement-related view, never student or provider references", async () => {
  const {service} = fixture(); const payment = await service.prepare("student", "lesson", policy);
  const view = await service.status("coach", payment.paymentId);
  assert.equal(view.coachAmount, 44000); assert.equal(view.providerOrderId, undefined);
  assert.equal(view.studentUid, undefined); assert.equal(view.providerPaymentKey, undefined);
});

test("fee calculation uses integer arithmetic even near safe integer limit", () => {
  assert.equal(calculateFees(999, policy).platformFee, 119);
  const result = calculateFees(Number.MAX_SAFE_INTEGER, policy);
  assert.equal(BigInt(result.platformFee), BigInt(Number.MAX_SAFE_INTEGER) * 1200n / 10000n);
  assert.equal(result.platformFee + result.coachAmount, Number.MAX_SAFE_INTEGER);
  for (const platformFeeBps of [-1, 10001, 1.5, Number.NaN]) {
    assert.throws(() => calculateFees(50000, {platformFeeBps}), rejected("failed-precondition"));
  }
});

test("preparation is disabled in real environments even if the flag is true", () => {
  const demo = {FUNCTIONS_EMULATOR: "true", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8280",
    FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9198", GCLOUD_PROJECT: "demo-onepoint-payments"};
  assert.doesNotThrow(() => assertLocalPreparation(true, demo));
  for (const [enabled, env] of [[false, demo], [true, {}],
    [true, {...demo, GCLOUD_PROJECT: "onlyonepoint-lesson"}],
    [true, {...demo, FIRESTORE_EMULATOR_HOST: ""}]] as const) {
    assert.throws(() => assertLocalPreparation(enabled, env), rejected("failed-precondition"));
  }
});

test("unconnected provider rejects both approval and refund", async () => {
  const gateway = new UnconnectedGateway();
  await assert.rejects(gateway.confirm({paymentId: "id", paymentKey: "key", providerOrderId: "order",
    amount: 50000, idempotencyKey: "confirm"}), rejected("unimplemented"));
  await assert.rejects(gateway.cancel({paymentId: "id", paymentKey: "key", amount: 50000,
    reason: "cancel", idempotencyKey: "refund"}), rejected("unimplemented"));
});
