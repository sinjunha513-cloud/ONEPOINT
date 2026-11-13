import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {FeePolicy, LessonDocument} from "./models";

export function documentId(value: unknown, name: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError("invalid-argument", `${name} must be a valid document ID.`);
  }
  return value;
}

export function requestId(data: unknown, key: "lessonId" | "paymentId"): string {
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).some((field) => field !== key)) {
    throw new HttpsError("invalid-argument", `Only ${key} is accepted; client amounts and states are not trusted.`);
  }
  return documentId((data as Record<string, unknown>)[key], key);
}

export function paymentIdFor(lessonId: string): string {
  return `op_${createHash("sha256").update(lessonId).digest("hex").slice(0, 48)}`;
}

export function validateLesson(lesson: LessonDocument, uid: string): number {
  if (lesson.studentUid !== uid) throw new HttpsError("permission-denied", "Only this lesson's student may prepare payment.");
  if (lesson.status !== "accepted") throw new HttpsError("failed-precondition", "The coach must accept the lesson first.");
  if (!Array.isArray(lesson.participantIds) || lesson.participantIds.length !== 2 ||
      !lesson.participantIds.includes(uid) || !lesson.participantIds.includes(lesson.instructorUid) ||
      lesson.instructorUid === uid || typeof lesson.instructorUid !== "string" || !lesson.instructorUid) {
    throw new HttpsError("failed-precondition", "Lesson participants are invalid.");
  }
  if (lesson.paymentStatus && lesson.paymentStatus !== "pending") {
    throw new HttpsError("failed-precondition", "This lesson already has a terminal payment state.");
  }
  if (!Number.isSafeInteger(lesson.price) || (lesson.price ?? 0) <= 0 || lesson.currency !== "KRW") {
    throw new HttpsError("failed-precondition", "A server-approved integer KRW price is required; no default price is assumed.");
  }
  return lesson.price!;
}

export function calculateFees(amount: number, policy: FeePolicy) {
  if (!Number.isSafeInteger(amount) || amount <= 0 ||
      !Number.isInteger(policy.platformFeeBps) || policy.platformFeeBps < 0 || policy.platformFeeBps > 10000) {
    throw new HttpsError("failed-precondition", "Invalid amount or platform fee policy.");
  }
  // Whole KRW, fee rounded down. Multiplication never goes through floats.
  const platformFee = Number(BigInt(amount) * BigInt(policy.platformFeeBps) / 10000n);
  return {platformFeeBps: policy.platformFeeBps, platformFeeRate: policy.platformFeeBps / 10000,
    platformFee, coachAmount: amount - platformFee};
}
