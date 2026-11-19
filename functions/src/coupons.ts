import {FieldValue, getFirestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {documentId, validateLesson} from "./domain";
import {platformFeeBps} from "./fee_policy";
import {LessonDocument} from "./models";
import {couponLifetimeMs, discountedQuote, koreaMonth, monthlyCompletions, monthlyLessonTarget} from "./reward_domain";

const options = {region: "asia-northeast3", maxInstances: 2, timeoutSeconds: 60, enforceAppCheck: false};
const stamp = () => FieldValue.serverTimestamp();
function input(request: CallableRequest, keys: string[]) {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data) ||
      Object.keys(request.data).some(key => !keys.includes(key))) {
    throw new HttpsError("invalid-argument", "요청 항목을 확인해 주세요.");
  }
  return request.data as Record<string, unknown>;
}
async function member(tx: Transaction, uid: string, studentOnly = true) {
  const account = (await tx.get(getFirestore().collection("users").doc(uid))).data();
  if (!account || account.profileCompleted !== true || (account.accountStatus ?? "active") !== "active" ||
      !["student", "coach"].includes(account.role)) {
    throw new HttpsError("permission-denied", "활성 수강생 또는 코치 계정이 필요합니다.");
  }
  if (studentOnly && account.role !== "student") {
    throw new HttpsError("permission-denied", "할인권은 수강생 계정만 받을 수 있고 사용할 수 있습니다.");
  }
  return account;
}

export const claimMonthlyCoupon = onCall(options, async request => {
  input(request, []); const uid = request.auth!.uid;
  return getFirestore().runTransaction(async tx => {
    const account = await member(tx, uid); const now = Date.now(); const month = koreaMonth(now);
    const couponId = `monthly_${month.key}`;
    const ref = getFirestore().collection("users").doc(uid).collection("coupons").doc(couponId);
    const existing = await tx.get(ref);
    if (existing.exists) return {couponId, alreadyClaimed: true};
    // Query by the actor's indexed UID only, keeping eligibility independent of
    // client counters and avoiding a newly-required composite index at rollout.
    const lessons = await tx.get(getFirestore().collection("lesson_requests")
      .where("studentUid", "==", uid));
    const count = monthlyCompletions(lessons.docs.map(doc => doc.data()), uid, account.role, now);
    if (count < monthlyLessonTarget) throw new HttpsError("failed-precondition", `이번 달 수강 완료한 레슨이 ${monthlyLessonTarget}회가 되면 받을 수 있습니다.`);
    tx.create(ref, {kind: "monthly_goal", rate: 10, earnedMonth: month.key, earnedRole: account.role,
      goalTarget: monthlyLessonTarget, status: "available", issuedAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + couponLifetimeMs),
      reservedLessonId: null, reservedAt: null, usedAt: null});
    return {couponId, alreadyClaimed: false};
  });
});

export const applyLessonCoupon = onCall(options, async request => {
  const data = input(request, ["lessonId", "couponId"]); const uid = request.auth!.uid;
  const lessonId = documentId(data.lessonId, "lessonId"), couponId = documentId(data.couponId, "couponId");
  return getFirestore().runTransaction(async tx => {
    await member(tx, uid);
    const lessonRef = getFirestore().collection("lesson_requests").doc(lessonId);
    const couponRef = getFirestore().collection("users").doc(uid).collection("coupons").doc(couponId);
    const lesson = (await tx.get(lessonRef)).data(); const coupon = (await tx.get(couponRef)).data();
    if (!lesson) throw new HttpsError("not-found", "레슨을 찾을 수 없습니다.");
    const price = validateLesson(lesson as LessonDocument, uid);
    if (coupon?.earnedRole !== "student") throw new HttpsError("failed-precondition", "수강생으로 받은 할인권만 사용할 수 있습니다.");
    if (lesson.paymentId || lesson.paymentStatus) throw new HttpsError("failed-precondition", "결제 준비 전의 레슨에만 할인권을 적용할 수 있습니다.");
    if (lesson.couponId === couponId && coupon?.status === "reserved" && coupon.reservedLessonId === lessonId) {
      return {lessonId, couponId, price};
    }
    if (lesson.couponId || !coupon || coupon.kind !== "monthly_goal" || coupon.rate !== 10 ||
        coupon.status !== "available" || !(coupon.expiresAt instanceof Timestamp) || coupon.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "이미 적용되었거나 사용할 수 없는 할인권입니다.");
    }
    const quote = discountedQuote(price, {platformFeeBps: platformFeeBps.value()});
    tx.update(lessonRef, {couponId, ...quote, couponAppliedAt: stamp(), updatedAt: stamp()});
    tx.update(couponRef, {status: "reserved", reservedLessonId: lessonId, reservedAt: stamp()});
    return {lessonId, couponId, price: quote.price};
  });
});

export const removeLessonCoupon = onCall(options, async request => {
  const data = input(request, ["lessonId"]); const uid = request.auth!.uid;
  const lessonId = documentId(data.lessonId, "lessonId");
  return getFirestore().runTransaction(async tx => {
    // Removing an old reservation restores the undiscounted price and grants
    // no new eligibility, including after the owner changes account roles.
    await member(tx, uid, false);
    const lessonRef = getFirestore().collection("lesson_requests").doc(lessonId);
    const lesson = (await tx.get(lessonRef)).data();
    if (!lesson || lesson.studentUid !== uid) throw new HttpsError("permission-denied", "본인 레슨만 변경할 수 있습니다.");
    if (!lesson.couponId) return {lessonId};
    if (lesson.status !== "accepted" || lesson.paymentId || lesson.paymentStatus) throw new HttpsError("failed-precondition", "결제 준비 전에만 할인권을 해제할 수 있습니다.");
    const couponRef = getFirestore().collection("users").doc(uid).collection("coupons").doc(documentId(lesson.couponId, "couponId"));
    const coupon = (await tx.get(couponRef)).data();
    if (!coupon || coupon.status !== "reserved" || coupon.reservedLessonId !== lessonId || !Number.isSafeInteger(lesson.originalPrice)) {
      throw new HttpsError("failed-precondition", "할인권 적용 기록을 확인해 주세요.");
    }
    tx.update(couponRef, release(coupon));
    tx.update(lessonRef, {price: lesson.originalPrice, couponId: FieldValue.delete(), originalPrice: FieldValue.delete(),
      discountAmount: FieldValue.delete(), platformFeeBps: FieldValue.delete(), platformFeeRate: FieldValue.delete(),
      platformFee: FieldValue.delete(), coachAmount: FieldValue.delete(), couponAppliedAt: FieldValue.delete(), updatedAt: stamp()});
    return {lessonId};
  });
});

function release(coupon: FirebaseFirestore.DocumentData) {
  return {status: coupon.expiresAt instanceof Timestamp && coupon.expiresAt.toMillis() > Date.now() ? "available" : "expired",
    reservedLessonId: null, reservedAt: null};
}
// Re-read the current state: Firestore events can be duplicated or arrive late.
export async function reconcileLessonCoupon(lessonId: string) {
  await getFirestore().runTransaction(async tx => {
    const lesson = (await tx.get(getFirestore().collection("lesson_requests").doc(lessonId))).data();
    if (!lesson?.couponId || !lesson.studentUid) return;
    const ref = getFirestore().collection("users").doc(lesson.studentUid).collection("coupons").doc(documentId(lesson.couponId, "couponId"));
    const coupon = (await tx.get(ref)).data();
    const payment = lesson.paymentId ? (await tx.get(getFirestore().collection("payments").doc(lesson.paymentId))).data() : undefined;
    if (!coupon || coupon.status !== "reserved" || coupon.reservedLessonId !== lessonId) return;
    if (payment?.paidAt || ["paid", "partial_refunded", "refunded"].includes(payment?.paymentStatus)) {
      tx.update(ref, {status: "used", usedAt: payment?.paidAt ?? stamp()});
    } else if (["cancelled", "rejected"].includes(lesson.status) && (!payment || ["cancelled", "failed"].includes(payment.paymentStatus))) {
      tx.update(ref, release(coupon));
    }
  });
}
export const syncLessonCoupon = onDocumentWritten({region: options.region, document: "lesson_requests/{lessonId}"},
  event => reconcileLessonCoupon(event.params.lessonId));
export const syncPaymentCoupon = onDocumentWritten({region: options.region, document: "payments/{paymentId}"}, async event => {
  const payment = event.data?.after.data() ?? event.data?.before.data();
  if (payment?.lessonId && payment?.couponId) await reconcileLessonCoupon(payment.lessonId);
});
