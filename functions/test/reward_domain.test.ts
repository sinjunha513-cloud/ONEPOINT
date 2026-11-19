import assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {discountedQuote, koreaMonth, monthlyCompletions, remainingFees} from "../src/reward_domain";
import {PaymentDocument} from "../src/models";

test("Korean month and role-specific completions exclude missing/future/pending records", () => {
  const now = Date.parse("2026-11-19T00:00:00Z");
  const lesson = (studentUid: string, instructorUid: string, time: string, status = "completed") =>
    ({studentUid, instructorUid, status, completedAt: Timestamp.fromDate(new Date(time))});
  const lessons = [lesson("me", "other", "2026-10-31T14:59:59Z"), lesson("me", "other", "2026-10-31T15:00:00Z"),
    lesson("me", "other", "2026-11-18T00:00:00Z"), lesson("other", "me", "2026-11-18T00:00:00Z"),
    lesson("me", "other", "2026-11-18T00:00:00Z", "accepted"), lesson("me", "other", "2026-11-30T15:00:00Z"),
    {studentUid: "me", status: "completed"}];
  assert.equal(monthlyCompletions(lessons, "me", "student", now), 2);
  assert.equal(monthlyCompletions(lessons, "me", "coach", now), 1);
  assert.equal(koreaMonth(Date.parse("2026-11-30T15:00:00Z")).key, "202612");
});
test("platform-funded ten percent keeps the original coach payout, including integer rounding", () => {
  const quote = discountedQuote(50000, {platformFeeBps: 1200});
  assert.equal(quote.price, 45000); assert.equal(quote.coachAmount, 44000); assert.equal(quote.platformFee, 1000);
  const odd = discountedQuote(10009, {platformFeeBps: 1200});
  assert.equal(odd.discountAmount, 1000); assert.equal(odd.coachAmount, 8808);
  assert.equal(odd.price, odd.platformFee + odd.coachAmount);
  assert.throws(() => discountedQuote(50000, {platformFeeBps: 900}));
  assert.throws(() => discountedQuote(Number.MAX_SAFE_INTEGER + 1, {platformFeeBps: 1200}));
});
test("discounted approval and refunds use the captured funded settlement", () => {
  const payment = {amount: 45000, platformFeeBps: 1200, coachAmount: 44000, platformFee: 1000, couponId: "monthly_202611"} as PaymentDocument;
  assert.deepEqual(remainingFees(payment, 45000), {platformFee: 1000, coachAmount: 44000});
  assert.deepEqual(remainingFees(payment, 22500), {platformFee: 500, coachAmount: 22000});
  assert.deepEqual(remainingFees(payment, 0), {platformFee: 0, coachAmount: 0});
  assert.throws(() => remainingFees(payment, 45001));
});
