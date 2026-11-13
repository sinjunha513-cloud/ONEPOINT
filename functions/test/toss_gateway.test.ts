import assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {DemoGateway, TossTestGateway} from "../src/toss_gateway";

const request = {paymentId: "payment", paymentKey: "key", providerOrderId: "order_123456", amount: 50000, idempotencyKey: "confirm_payment"};
const done = {paymentKey: "key", orderId: "order_123456", totalAmount: 50000, balanceAmount: 50000, currency: "KRW", status: "DONE", method: "카드"};
const code = (expected: string) => (error: unknown) => error instanceof HttpsError && error.code === expected;

test("production and missing secrets are rejected before network calls", () => {
  for (const secret of ["", "live_sk_secret", "live_gsk_secret", "DEMO_ONLY_NO_REAL_KEY"]) assert.throws(() => new TossTestGateway(secret), code("failed-precondition"));
  assert.throws(() => new DemoGateway({}), code("failed-precondition"));
});
test("approved PG response is reused without a second POST", async () => {
  let calls = 0;
  const transport = async (_url: unknown, options?: RequestInit) => { calls++; assert.equal(options?.method, "GET"); return new Response(JSON.stringify(done)); };
  const result = await new TossTestGateway("test_sk_example", transport as typeof fetch).confirm(request);
  assert.equal(result.amount, 50000); assert.equal(calls, 1);
});
test("unapproved PG authentication is followed by approval with server amount and idempotency key", async () => {
  const calls: RequestInit[] = [];
  const transport = async (_url: unknown, options?: RequestInit) => {
    calls.push(options!);
    return new Response(JSON.stringify(calls.length === 1 ? {...done, status: "IN_PROGRESS"} : done));
  };
  await new TossTestGateway("test_sk_example", transport as typeof fetch).confirm(request);
  assert.equal(calls.length, 2);
  assert.equal((JSON.parse(calls[1].body as string) as {amount: number}).amount, 50000);
  assert.equal((calls[1].headers as Record<string, string>)["Idempotency-Key"], "confirm_payment");
});
test("PG unavailability never masquerades as successful payment", async () => {
  const transport = async () => { throw new Error("network failure"); };
  await assert.rejects(new TossTestGateway("test_sk_example", transport as typeof fetch).confirm(request), code("unavailable"));
});
test("invalid PG amounts and currency are rejected", async () => {
  for (const response of [{...done, currency: "USD"}, {...done, balanceAmount: -1}, {...done, totalAmount: 1.5}]) {
    const transport = async () => new Response(JSON.stringify(response));
    await assert.rejects(new TossTestGateway("test_sk_example", transport as typeof fetch).get("key"), code("data-loss"));
  }
});
