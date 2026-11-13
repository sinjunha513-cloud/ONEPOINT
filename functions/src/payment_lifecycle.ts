import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {calculateFees, documentId} from "./domain";
import {PaymentDocument, supportedSports} from "./models";
import {Gateway, GatewayPayment} from "./toss_gateway";
import {projectPayment} from "./payment_service";

const stamp = () => FieldValue.serverTimestamp();
const lease = () => Timestamp.fromMillis(Date.now() + 90000);
const busy = (operation: FirebaseFirestore.DocumentData | undefined) =>
  ["confirming", "refunding"].includes(operation?.operation) &&
  operation?.leaseUntil instanceof Timestamp && operation.leaseUntil.toMillis() > Date.now();

export class PaymentLifecycle {
  constructor(private readonly db: Firestore, private readonly gateway: Gateway) {}

  async accept(uid: string, lessonId: string, price: number) {
    if (!Number.isSafeInteger(price) || price < 100 || price > 10000000) {
      throw new HttpsError("invalid-argument", "레슨 금액은 100원~1,000만원 사이의 정수로 입력해 주세요.");
    }
    const ref = this.db.collection("lesson_requests").doc(lessonId);
    await this.db.runTransaction(async (tx) => {
      const lesson = (await tx.get(ref)).data();
      const coach = (await tx.get(this.db.collection("users").doc(uid))).data();
      const profile = (await tx.get(this.db.collection("instructors").doc(uid))).data();
      if (!lesson) throw new HttpsError("not-found", "레슨을 찾을 수 없습니다.");
      if (!(supportedSports as readonly string[]).includes(lesson.sport)) throw new HttpsError("failed-precondition", "지원하지 않는 종목입니다. 코치 프로필을 확인해 주세요.");
      if (lesson.instructorUid !== uid || coach?.role !== "coach" || profile?.status !== "approved") {
        throw new HttpsError("permission-denied", "담당 승인 코치만 레슨 금액을 확정할 수 있습니다.");
      }
      if (lesson.status === "accepted" && lesson.price === price) return;
      if (lesson.status !== "pending" || lesson.paymentId) throw new HttpsError("failed-precondition", "대기 중인 신청만 수락할 수 있습니다.");
      // This is an authorized coach's quote, never a student's payment amount.
      tx.update(ref, {status: "accepted", price, currency: "KRW", updatedAt: stamp()});
    });
    return {lessonId, status: "accepted", price, currency: "KRW"};
  }

  async confirm(uid: string, paymentId: string, paymentKey: string) {
    if (typeof paymentKey !== "string" || paymentKey.length < 1 || paymentKey.length > 200) {
      throw new HttpsError("invalid-argument", "결제 인증값이 올바르지 않습니다.");
    }
    const ref = this.db.collection("payments").doc(paymentId);
    const gatewayRef = this.db.collection("payment_gateway_records").doc(paymentId);
    const prepared = await this.db.runTransaction(async (tx) => {
      const payment = (await tx.get(ref)).data() as PaymentDocument | undefined;
      if (!payment) throw new HttpsError("not-found", "결제 준비 내역이 없습니다.");
      const lesson = (await tx.get(this.db.collection("lesson_requests").doc(payment.lessonId))).data();
      const operation = (await tx.get(gatewayRef)).data();
      if (payment.studentUid !== uid) throw new HttpsError("permission-denied", "본인의 결제만 승인할 수 있습니다.");
      if (payment.paymentStatus === "paid" || payment.paymentStatus === "partial_refunded") return {payment, done: true};
      if (payment.paymentStatus !== "pending" || lesson?.status !== "accepted" || lesson.paymentId !== paymentId || lesson.price !== payment.amount) {
        throw new HttpsError("failed-precondition", "결제할 수 있는 레슨 상태가 아닙니다.");
      }
      if (operation?.providerPaymentKey && operation.providerPaymentKey !== paymentKey) {
        throw new HttpsError("failed-precondition", "기존 결제 인증값과 일치하지 않습니다.");
      }
      if (busy(operation)) throw new HttpsError("aborted", "결제를 확인 중입니다. 잠시 후 다시 확인해 주세요.");
      tx.set(gatewayRef, {paymentId, providerPaymentKey: paymentKey, operation: "confirming",
        confirmationIdempotencyKey: `confirm_${paymentId}`, leaseUntil: lease(), updatedAt: stamp()}, {merge: true});
      return {payment, done: false};
    });
    if (prepared.done) return projectPayment(prepared.payment);
    const payment = prepared.payment;
    let result: GatewayPayment;
    try {
      result = await this.gateway.confirm({paymentId, paymentKey, providerOrderId: payment.providerOrderId,
        amount: payment.amount, idempotencyKey: `confirm_${paymentId}`});
    } catch (error) {
      // Ambiguous transport failures keep the stored reference for reconciliation.
      // A verified rejection permits another authentication attempt; never mark paid.
      if (error instanceof HttpsError && error.code === "failed-precondition") {
        await this.db.runTransaction(async (tx) => {
          const current = (await tx.get(ref)).data();
          const op = (await tx.get(gatewayRef)).data();
          if (current?.paymentStatus === "pending" && op?.providerPaymentKey === paymentKey) tx.delete(gatewayRef);
        });
      }
      throw error;
    }
    return this.commitVerified(paymentId, result);
  }

  async reconcile(uid: string, paymentId: string) {
    const payment = (await this.db.collection("payments").doc(paymentId).get()).data();
    const account = (await this.db.collection("users").doc(uid).get()).data();
    if (!payment || (account?.role !== "admin" && payment.studentUid !== uid && payment.instructorUid !== uid)) {
      throw new HttpsError("permission-denied", "결제 조회 권한이 없습니다.");
    }
    return this.reconcileFromProvider(paymentId);
  }

  async reconcileFromProvider(paymentId: string) {
    const record = (await this.db.collection("payment_gateway_records").doc(paymentId).get()).data();
    if (!record?.providerPaymentKey) throw new HttpsError("failed-precondition", "확인할 PG 결제 기록이 없습니다.");
    return this.commitVerified(paymentId, await this.gateway.get(record.providerPaymentKey));
  }

  private async commitVerified(paymentId: string, verified: GatewayPayment, refundId?: string) {
    const ref = this.db.collection("payments").doc(paymentId);
    const gatewayRef = this.db.collection("payment_gateway_records").doc(paymentId);
    return this.db.runTransaction(async (tx) => {
      const payment = (await tx.get(ref)).data() as PaymentDocument | undefined;
      const gateway = (await tx.get(gatewayRef)).data();
      const currentRefundId = refundId ?? (gateway?.operation === "refunding" ? gateway.refundId : undefined);
      if (!payment) throw new HttpsError("not-found", "결제 기록이 없습니다.");
      const lessonRef = this.db.collection("lesson_requests").doc(payment.lessonId);
      const lesson = (await tx.get(lessonRef)).data();
      const refundRef = currentRefundId ? ref.collection("refunds").doc(currentRefundId) : null;
      if (refundRef) await tx.get(refundRef);
      if (!lesson || lesson.paymentId !== paymentId || verified.providerOrderId !== payment.providerOrderId ||
          verified.paymentKey !== gateway?.providerPaymentKey || verified.amount !== payment.amount || verified.currency !== payment.currency) {
        throw new HttpsError("data-loss", "결제 금액·주문 검증에 실패했습니다. 관리자 확인이 필요합니다.");
      }
      const refunded = payment.amount - verified.balanceAmount;
      if (refunded < payment.refundedAmount || (verified.status === "DONE" && refunded !== 0) ||
          (verified.status === "CANCELED" && refunded !== payment.amount) ||
          (verified.status === "PARTIAL_CANCELED" && (refunded <= 0 || refunded >= payment.amount))) {
        throw new HttpsError("data-loss", "PG 환불 상태 검증에 실패했습니다.");
      }
      const firstPaid = payment.paymentStatus === "pending";
      const refundDelta = refunded - payment.refundedAmount;
      const fullRefund = refunded === payment.amount;
      const state = fullRefund ? "refunded" : refunded > 0 ? "partial_refunded" : "paid";
      if (firstPaid && lesson.status !== "accepted") throw new HttpsError("failed-precondition", "취소 또는 완료된 레슨은 확정할 수 없습니다.");
      if (refunded > 0 && payment.payoutStatus === "completed") throw new HttpsError("failed-precondition", "지급 완료 거래는 관리자 정산 조정이 필요합니다.");
      const fees = verified.balanceAmount === 0 ? {platformFee: 0, coachAmount: 0} : calculateFees(verified.balanceAmount, {platformFeeBps: payment.platformFeeBps});
      const payoutStatus = fullRefund ? "cancelled" : lesson.status === "completed" ? "held" : "pending";
      const update: FirebaseFirestore.DocumentData = {
        paymentStatus: state, refundedAmount: refunded, paymentMethod: verified.paymentMethod,
        netPlatformFee: fees.platformFee, netCoachAmount: fees.coachAmount, updatedAt: stamp(),
        ...(firstPaid ? {paidAt: stamp(), payoutStatus: "pending"} : {}),
        ...(refundDelta > 0 ? {refundedAt: stamp(), payoutStatus, refundStatus: "processed"} : {}),
      };
      tx.update(ref, update);
      tx.update(lessonRef, {paymentStatus: state,
        ...(firstPaid ? {status: "confirmed", confirmedAt: stamp()} : {}),
        ...(fullRefund && lesson.status !== "completed" ? {status: "cancelled", cancelledAt: stamp()} : {}), updatedAt: stamp()});
      tx.set(gatewayRef, {operation: "idle", leaseUntil: Timestamp.fromMillis(0), lastVerifiedAt: stamp()}, {merge: true});
      if (refundRef && refundDelta > 0) tx.set(refundRef, {status: "succeeded", refundedAt: stamp()}, {merge: true});
      if (refundDelta > 0) tx.set(this.db.collection("refund_requests").doc(paymentId), {status: "processed", updatedAt: stamp()}, {merge: true});
      if (fullRefund) this.clearPair(tx, lesson);
      if (firstPaid || refundDelta > 0) {
        tx.set(this.db.collection("payment_stats").doc("summary"), {
          ...(firstPaid ? {paidCount: FieldValue.increment(1), grossApprovedAmount: FieldValue.increment(payment.amount)} : {}),
          ...(refundDelta > 0 ? {refundedAmount: FieldValue.increment(refundDelta),
            ...(lesson.status === "completed" ? {
              completedAmount: FieldValue.increment(-refundDelta),
              platformFeeTotal: FieldValue.increment(fees.platformFee - (payment.netPlatformFee ?? payment.platformFee)),
              coachReadyTotal: FieldValue.increment(fees.coachAmount - (payment.netCoachAmount ?? payment.coachAmount)),
            } : {}),
            ...(payment.refundedAmount === 0 ? {refundCount: FieldValue.increment(1)} : {})} : {}), updatedAt: stamp(),
        }, {merge: true});
      }
      return projectPayment({...payment, ...update});
    });
  }

  async requestRefund(uid: string, paymentId: string, reason: string) {
    const ref = this.db.collection("payments").doc(paymentId);
    await this.db.runTransaction(async (tx) => {
      const payment = (await tx.get(ref)).data();
      const op = (await tx.get(this.db.collection("payment_gateway_records").doc(paymentId))).data();
      if (!payment || payment.studentUid !== uid) throw new HttpsError("permission-denied", "본인 결제만 환불 요청할 수 있습니다.");
      if (!["paid", "partial_refunded"].includes(payment.paymentStatus) || payment.payoutStatus === "completed" || busy(op)) {
        throw new HttpsError("failed-precondition", "현재 환불 요청할 수 없는 상태입니다.");
      }
      tx.set(this.db.collection("refund_requests").doc(paymentId), {
        paymentId, lessonId: payment.lessonId, studentUid: uid, instructorUid: payment.instructorUid,
        reason, status: "pending", updatedAt: stamp(),
      }, {merge: true});
      tx.update(ref, {refundStatus: "requested", payoutStatus: "held", updatedAt: stamp()});
    });
    return {paymentId, refundStatus: "requested"};
  }

  async refund(uid: string, paymentId: string, refundId: string, amount: number | undefined, reason: string) {
    documentId(refundId, "refundId");
    const ref = this.db.collection("payments").doc(paymentId);
    const opRef = this.db.collection("payment_gateway_records").doc(paymentId);
    const refundRef = ref.collection("refunds").doc(refundId);
    const claim = await this.db.runTransaction(async (tx) => {
      const payment = (await tx.get(ref)).data() as PaymentDocument | undefined;
      const caller = (await tx.get(this.db.collection("users").doc(uid))).data();
      const op = (await tx.get(opRef)).data();
      const prior = (await tx.get(refundRef)).data();
      if (!payment) throw new HttpsError("not-found", "결제 내역이 없습니다.");
      const lesson = (await tx.get(this.db.collection("lesson_requests").doc(payment.lessonId))).data();
      const admin = caller?.role === "admin";
      if (!admin && !(caller?.role === "coach" && payment.instructorUid === uid)) throw new HttpsError("permission-denied", "코치 취소 또는 관리자 환불만 직접 처리합니다. 수강생은 환불을 요청해 주세요.");
      if (prior?.status === "succeeded") return {payment, done: true, amount: prior.amount as number, key: op?.providerPaymentKey as string};
      const remaining = payment.amount - payment.refundedAmount;
      const requested = prior?.amount ?? amount ?? remaining;
      if (!Number.isSafeInteger(requested) || requested <= 0 || requested > remaining ||
          (!admin && requested !== remaining) || !["paid", "partial_refunded"].includes(payment.paymentStatus) ||
          !lesson || lesson.status !== "confirmed" || payment.payoutStatus === "completed" || !op?.providerPaymentKey) {
        throw new HttpsError("failed-precondition", "진행 전 레슨의 유효한 환불 금액을 확인해 주세요. 완료 레슨은 분쟁 처리 절차가 필요합니다.");
      }
      if (prior && amount !== undefined && prior.amount !== amount) throw new HttpsError("invalid-argument", "동일 환불 요청의 금액을 변경할 수 없습니다.");
      if (op?.operation === "refunding" && op.refundId !== refundId) throw new HttpsError("aborted", "이전 환불의 PG 상태를 재확인한 후 다음 환불을 요청해 주세요.");
      if (busy(op)) throw new HttpsError("aborted", "다른 결제 처리가 진행 중입니다. 잠시 후 다시 시도해 주세요.");
      tx.set(refundRef, {refundId, paymentId, amount: requested, reason, requestedBy: uid,
        status: "pending", idempotencyKey: `refund_${paymentId}_${refundId}`, createdAt: stamp(), refundedAt: null}, {merge: true});
      tx.set(opRef, {operation: "refunding", refundId, leaseUntil: lease(), updatedAt: stamp()}, {merge: true});
      tx.update(ref, {payoutStatus: "held", updatedAt: stamp()});
      return {payment, done: false, amount: requested as number, key: op.providerPaymentKey as string};
    });
    if (claim.done) return projectPayment(claim.payment);
    const verified = await this.gateway.cancel({paymentId, paymentKey: claim.key, amount: claim.amount,
      reason, idempotencyKey: `refund_${paymentId}_${refundId}`});
    return this.commitVerified(paymentId, verified, refundId);
  }

  async cancelUnpaid(uid: string, lessonId: string) {
    const ref = this.db.collection("lesson_requests").doc(lessonId);
    await this.db.runTransaction(async (tx) => {
      const lesson = (await tx.get(ref)).data();
      const caller = (await tx.get(this.db.collection("users").doc(uid))).data();
      if (!lesson || (caller?.role !== "admin" && lesson.studentUid !== uid && lesson.instructorUid !== uid)) throw new HttpsError("permission-denied", "취소할 권한이 없습니다.");
      const paymentRef = lesson.paymentId ? this.db.collection("payments").doc(lesson.paymentId) : null;
      const payment = paymentRef ? (await tx.get(paymentRef)).data() : undefined;
      const op = lesson.paymentId ? (await tx.get(this.db.collection("payment_gateway_records").doc(lesson.paymentId))).data() : undefined;
      if (lesson.status === "cancelled") return;
      if (!["pending", "accepted"].includes(lesson.status) || (payment && payment.paymentStatus !== "pending") || busy(op) || op?.providerPaymentKey) throw new HttpsError("failed-precondition", "승인 상태를 확인 중이거나 결제된 레슨은 환불 절차를 이용해 주세요.");
      tx.update(ref, {status: "cancelled", updatedAt: stamp(), ...(payment ? {paymentStatus: "cancelled"} : {})});
      if (paymentRef) tx.update(paymentRef, {paymentStatus: "cancelled", payoutStatus: "cancelled", cancelledAt: stamp(), updatedAt: stamp()});
      this.clearPair(tx, lesson);
    });
    return {lessonId, status: "cancelled"};
  }

  async complete(uid: string, lessonId: string, score: number, feedback: string, signatureMove: string) {
    if (!Number.isFinite(score) || score < 1 || score > 5 || feedback.length > 1000 || signatureMove.trim().length > 40) throw new HttpsError("invalid-argument", "평가·피드백·시그니처 기술을 확인해 주세요.");
    const ref = this.db.collection("lesson_requests").doc(lessonId);
    await this.db.runTransaction(async (tx) => {
      const lesson = (await tx.get(ref)).data();
      const caller = (await tx.get(this.db.collection("users").doc(uid))).data();
      if (!lesson?.paymentId) throw new HttpsError("failed-precondition", "유료 레슨 결제 기록이 필요합니다.");
      const instructor = (await tx.get(this.db.collection("instructors").doc(lesson.instructorUid))).data();
      const signatureBadgeId = typeof instructor?.signatureBadgeId === "string" ? instructor.signatureBadgeId :
        (typeof lesson.signatureBadgeId === "string" ? lesson.signatureBadgeId : undefined);
      const signatureBadge = signatureBadgeId ?
        (await tx.get(this.db.collection("signature_badges").doc(signatureBadgeId))).data() : undefined;
      const paymentRef = this.db.collection("payments").doc(lesson.paymentId);
      const payment = (await tx.get(paymentRef)).data() as PaymentDocument | undefined;
      const studentRef = this.db.collection("users").doc(lesson.studentUid);
      const student = (await tx.get(studentRef)).data();
      const op = (await tx.get(this.db.collection("payment_gateway_records").doc(lesson.paymentId))).data();
      if (caller?.role !== "admin" && (uid !== lesson.instructorUid || caller?.role !== "coach" || instructor?.status !== "approved")) throw new HttpsError("permission-denied", "담당 코치 또는 관리자만 완료할 수 있습니다.");
      if (lesson.status === "completed") return;
      if (lesson.status !== "confirmed" || !payment || !["paid", "partial_refunded"].includes(payment.paymentStatus) ||
          payment.payoutStatus === "held" || busy(op) || !student) throw new HttpsError("failed-precondition", "결제 확정·환불 상태를 먼저 확인해 주세요.");
      if (signatureBadgeId && !signatureBadge) throw new HttpsError("failed-precondition", "선택한 시그니처 뱃지를 다시 등록해 주세요.");
      const awardedSignature = (typeof signatureBadge?.name === "string" && signatureBadge.name.trim()) ||
        (typeof instructor?.signatureMove === "string" && instructor.signatureMove.trim()) ||
        signatureMove.trim() || (typeof lesson.signatureMove === "string" ? lesson.signatureMove.trim() : "");
      if (!awardedSignature) throw new HttpsError("failed-precondition", "시그니처 뱃지를 먼저 등록해 주세요.");
      const signatureBadgeColorIndex = typeof signatureBadge?.colorIndex === "number" ? signatureBadge.colorIndex : undefined;
      tx.update(ref, {status: "completed", reviewScore: score, reviewFeedback: feedback,
        attendanceBadge: {instructorUid: lesson.instructorUid, instructorName: lesson.instructorName,
          signatureMove: awardedSignature,
          ...(signatureBadgeId ? {signatureBadgeId} : {}),
          ...(signatureBadgeColorIndex !== undefined ? {signatureBadgeColorIndex} : {}),
          sport: lesson.sport, awardedAt: stamp(), verifiedBy: uid}, completedAt: stamp(), updatedAt: stamp()});
      tx.update(studentRef, {lastCompletedLessonId: lessonId, lessonCount: FieldValue.increment(1),
        reviewScores: [...(student.reviewScores ?? []), score],
        ...(lesson.isInstructorInitiated ? {teacherMatchCount: FieldValue.increment(1)} : {})});
      tx.update(paymentRef, {payoutStatus: "ready", updatedAt: stamp()});
      tx.set(this.db.collection("payment_stats").doc("summary"), {completedLessonCount: FieldValue.increment(1),
        completedAmount: FieldValue.increment(payment.amount - payment.refundedAmount),
        platformFeeTotal: FieldValue.increment(payment.netPlatformFee ?? payment.platformFee),
        coachReadyTotal: FieldValue.increment(payment.netCoachAmount ?? payment.coachAmount), updatedAt: stamp()}, {merge: true});
      this.clearPair(tx, lesson);
    });
    return {lessonId, status: "completed", payoutStatus: "ready"};
  }

  private clearPair(tx: FirebaseFirestore.Transaction, lesson: FirebaseFirestore.DocumentData) {
    tx.delete(this.db.collection("active_lesson_requests").doc(`${lesson.studentUid}_${lesson.instructorUid}`));
    tx.delete(this.db.collection("active_lesson_requests").doc(`${lesson.instructorUid}_${lesson.studentUid}`));
  }
}
