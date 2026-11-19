import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {calculateFees} from "./domain";
import {FeePolicy, PaymentDocument} from "./models";

export const monthlyLessonTarget = 10;
export const couponLifetimeMs = 30 * 24 * 60 * 60 * 1000;
export function koreaMonth(now: number) {
  const date = new Date(now + 9 * 60 * 60 * 1000);
  const year = date.getUTCFullYear(), month = date.getUTCMonth();
  return {key: `${year}${String(month + 1).padStart(2, "0")}`,
    start: Date.UTC(year, month, 1) - 9 * 60 * 60 * 1000,
    end: Date.UTC(year, month + 1, 1) - 9 * 60 * 60 * 1000};
}
export function monthlyCompletions(lessons: FirebaseFirestore.DocumentData[], uid: string, role: string, now: number) {
  const month = koreaMonth(now);
  const field = role === "coach" ? "instructorUid" : "studentUid";
  if (!["coach", "student"].includes(role)) return 0;
  return lessons.filter(lesson => lesson[field] === uid && lesson.status === "completed" &&
    lesson.completedAt instanceof Timestamp && lesson.completedAt.toMillis() >= month.start &&
    lesson.completedAt.toMillis() < month.end && lesson.completedAt.toMillis() <= now).length;
}
export function discountedQuote(originalPrice: number, policy: FeePolicy) {
  const original = calculateFees(originalPrice, policy);
  const discountAmount = Number(BigInt(originalPrice) / 10n);
  if (discountAmount <= 0 || original.platformFee < discountAmount) {
    throw new HttpsError("failed-precondition", "플랫폼 수수료로 할인액을 부담할 수 없는 레슨입니다.");
  }
  return {originalPrice, discountAmount, price: originalPrice - discountAmount,
    platformFeeBps: original.platformFeeBps, platformFeeRate: original.platformFeeRate,
    platformFee: original.platformFee - discountAmount, coachAmount: original.coachAmount};
}
// Refunds reduce the captured settlement proportionally; the original coach
// payout is preserved at purchase, instead of charging the coupon to the coach.
export function remainingFees(payment: PaymentDocument, balance: number) {
  if (!Number.isSafeInteger(balance) || balance < 0 || balance > payment.amount) {
    throw new HttpsError("data-loss", "환불 잔액을 확인해 주세요.");
  }
  if (balance === 0) return {platformFee: 0, coachAmount: 0};
  if (!payment.couponId) return calculateFees(balance, {platformFeeBps: payment.platformFeeBps});
  const coachAmount = Number(BigInt(payment.coachAmount) * BigInt(balance) / BigInt(payment.amount));
  return {platformFee: balance - coachAmount, coachAmount};
}
