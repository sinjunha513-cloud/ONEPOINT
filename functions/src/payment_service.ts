import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {calculateFees, paymentIdFor, validateLesson} from "./domain";
import {FeePolicy, PaymentDocument} from "./models";
import {PaymentStore} from "./store";

export class PaymentService {
  constructor(private readonly store: PaymentStore,
    private readonly gatewayMode: "test" | "demo" = "test") {}

  async prepare(uid: string, lessonId: string, policy: FeePolicy): Promise<PaymentDocument> {
    const paymentId = paymentIdFor(lessonId);
    return this.store.transaction(async (transaction) => {
      const lesson = await transaction.lesson(lessonId);
      if (!lesson) throw new HttpsError("not-found", "Lesson not found.");
      const amount = validateLesson(lesson, uid);
      const student = await transaction.account(uid);
      const coach = await transaction.account(lesson.instructorUid);
      const instructor = await transaction.instructor(lesson.instructorUid);
      const existing = await transaction.payment(paymentId);
      if (student?.role !== "student" || student.profileCompleted !== true ||
          coach?.role !== "coach" || instructor?.status !== "approved" ||
          instructor.uid !== lesson.instructorUid || instructor.userId !== lesson.instructorUid) {
        throw new HttpsError("failed-precondition", "Completed student and approved coach accounts are required.");
      }
      if (lesson.paymentId && lesson.paymentId !== paymentId) {
        throw new HttpsError("failed-precondition", "Lesson has a different payment reference.");
      }
      if (existing) {
        if (existing.lessonId !== lessonId || existing.studentUid !== uid ||
            existing.instructorUid !== lesson.instructorUid || existing.amount !== amount ||
            existing.currency !== "KRW" || existing.mode !== this.gatewayMode || existing.paymentStatus !== "pending" ||
            lesson.paymentId !== paymentId || lesson.paymentStatus !== "pending") {
          throw new HttpsError("failed-precondition", "Existing payment cannot be reused or its price has changed.");
        }
        // Preserve the fee policy and timestamp captured by the first request.
        return existing;
      }
      if (lesson.paymentId || lesson.paymentStatus) {
        throw new HttpsError("failed-precondition", "Payment reference is incomplete; reconciliation is required.");
      }
      const now = this.store.now();
      const payment: PaymentDocument = {
        schemaVersion: 1, paymentId, lessonId, studentUid: uid, instructorUid: lesson.instructorUid,
        amount, currency: "KRW", ...calculateFees(amount, policy),
        paymentStatus: "pending", payoutStatus: "pending", provider: this.gatewayMode === "demo" ? "demo" : "toss", mode: this.gatewayMode,
        providerOrderId: paymentId, paymentMethod: null, refundedAmount: 0,
        createdAt: now, updatedAt: now, paidAt: null, cancelledAt: null, refundedAt: null,
      };
      // No PG request, confirmed lesson, paid flag, refund, or payout is created.
      transaction.createPayment(paymentId, payment);
      transaction.linkLesson(lessonId, paymentId);
      return payment;
    });
  }

  async status(uid: string, paymentId: string): Promise<Record<string, unknown>> {
    const [payment, account] = await Promise.all([this.store.payment(paymentId), this.store.account(uid)]);
    if (!payment) throw new HttpsError("not-found", "Payment not found.");
    const admin = account?.role === "admin";
    const student = payment.studentUid === uid;
    const coach = payment.instructorUid === uid && account?.role === "coach";
    if (!admin && !student && !coach) throw new HttpsError("permission-denied", "Payment access denied.");
    const lesson = await this.store.lesson?.(payment.lessonId);
    return {...projectPayment(payment, coach && !admin && !student),
      lessonStatus: lesson?.status ?? "unknown", instructorName: lesson?.instructorName ?? payment.instructorUid,
      studentName: lesson?.studentName ?? "수강생", signatureMove: lesson?.signatureMove ?? ""};
  }
}

export function projectPayment(payment: PaymentDocument, coachOnly = false): Record<string, unknown> {
  const view: Record<string, unknown> = {
    schemaVersion: payment.schemaVersion, paymentId: payment.paymentId, lessonId: payment.lessonId,
    instructorUid: payment.instructorUid, amount: payment.amount, currency: payment.currency,
    platformFeeBps: payment.platformFeeBps, platformFeeRate: payment.platformFeeRate,
    platformFee: payment.platformFee, coachAmount: payment.coachAmount,
    paymentStatus: payment.paymentStatus, payoutStatus: payment.payoutStatus,
    refundedAmount: payment.refundedAmount,
    refundStatus: payment.refundStatus ?? "none",
    netPlatformFee: payment.netPlatformFee ?? payment.platformFee,
    netCoachAmount: payment.netCoachAmount ?? payment.coachAmount,
    createdAt: isoTime(payment.createdAt), paidAt: isoTime(payment.paidAt),
    cancelledAt: isoTime(payment.cancelledAt), refundedAt: isoTime(payment.refundedAt),
  };
  if (!coachOnly) Object.assign(view, {
    studentUid: payment.studentUid, provider: payment.provider, mode: payment.mode,
    providerOrderId: payment.providerOrderId, paymentMethod: payment.paymentMethod,
  });
  return view;
}

function isoTime(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}
