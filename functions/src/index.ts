import {getApps, initializeApp} from "firebase-admin/app";
import {createHash} from "node:crypto";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {HttpsError, onCall, onRequest, CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {assertLocalPreparation, checkoutBaseUrl, paymentGatewayMode, platformFeeBps, preparationEnabled, tossTestClientKey, tossTestSecretKey} from "./config";
import {documentId, requestId} from "./domain";
import {PaymentDocument} from "./models";
import {PaymentService, projectPayment} from "./payment_service";
import {PaymentLifecycle} from "./payment_lifecycle";
import {DemoGateway, TossTestGateway, Gateway} from "./toss_gateway";
import {FirestorePaymentStore} from "./store";
if (getApps().length === 0) initializeApp();
const db = getFirestore();
const options = {region: "asia-northeast3", maxInstances: 2, timeoutSeconds: 60, enforceAppCheck: false};
const secretOptions = {...options, secrets: [tossTestSecretKey]};
async function authenticated(request: CallableRequest): Promise<string> {
  if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const member = (await db.collection("users").doc(request.auth.uid).get()).data();
  if (!member || member.profileCompleted !== true || (member.accountStatus ?? "active") !== "active") throw new HttpsError("permission-denied", "정지 또는 삭제된 계정입니다.");
  return request.auth.uid;
}
export function object(data: unknown, allowed: string[]): Record<string, unknown> {
  if (!data || typeof data !== "object" || Array.isArray(data) || Object.keys(data).some((key) => !allowed.includes(key))) throw new HttpsError("invalid-argument", "요청 항목을 확인해 주세요.");
  return data as Record<string, unknown>;
}
function text(value: unknown, max = 200): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) throw new HttpsError("invalid-argument", "필수 입력을 확인해 주세요.");
  return value.trim();
}
function enabled() {
  if (!preparationEnabled.value()) throw new HttpsError("failed-precondition", "결제 테스트 키 설정이 아직 완료되지 않았습니다.");
  if (paymentGatewayMode.value() === "demo") assertLocalPreparation(true);
  else if (paymentGatewayMode.value() !== "toss-test") throw new HttpsError("failed-precondition", "운영 결제는 활성화되어 있지 않습니다.");
}
function gateway(): Gateway {
  enabled();
  return paymentGatewayMode.value() === "demo" ? new DemoGateway(process.env, db) : new TossTestGateway(tossTestSecretKey.value());
}
function service() { return new PaymentService(new FirestorePaymentStore(db), paymentGatewayMode.value() === "demo" ? "demo" : "test"); }
const logic = () => new PaymentLifecycle(db, gateway());
const noGateway = {} as Gateway;

export const acceptPaidLesson = onCall(options, async (request) => {
  const uid = await authenticated(request); enabled(); const input = object(request.data, ["lessonId", "price"]);
  return new PaymentLifecycle(db, noGateway).accept(uid, documentId(input.lessonId, "lessonId"), input.price as number);
});
export const preparePayment = onCall(options, async (request) => {
  const uid = await authenticated(request); const lessonId = requestId(request.data, "lessonId"); enabled();
  const payment = await service().prepare(uid, lessonId, {platformFeeBps: platformFeeBps.value()});
  logger.info("payment_prepared", {lessonId, paymentId: payment.paymentId});
  return {...projectPayment(payment), customerKey: `cust_${createHash("sha256").update(uid).digest("hex").slice(0, 32)}`,
    clientKey: tossTestClientKey.value(), checkoutBaseUrl: checkoutBaseUrl.value()};
});
export const getPaymentStatus = onCall(options, async (request) => service().status(await authenticated(request), requestId(request.data, "paymentId")));
export const confirmPayment = onCall(secretOptions, async (request) => {
  const uid = await authenticated(request); const input = object(request.data, ["paymentId", "paymentKey"]);
  return logic().confirm(uid, documentId(input.paymentId, "paymentId"), text(input.paymentKey));
});
export const reconcilePayment = onCall(secretOptions, async (request) => logic().reconcile(await authenticated(request), requestId(request.data, "paymentId")));
export const cancelPayment = onCall(secretOptions, async (request) => {
  const uid = await authenticated(request); const input = object(request.data, ["paymentId", "refundId", "amount", "reason"]);
  return logic().refund(uid, documentId(input.paymentId, "paymentId"), documentId(input.refundId, "refundId"), input.amount as number | undefined, text(input.reason));
});
export const requestPaymentRefund = onCall(options, async (request) => {
  const uid = await authenticated(request); enabled(); const input = object(request.data, ["paymentId", "reason"]);
  return new PaymentLifecycle(db, noGateway).requestRefund(uid, documentId(input.paymentId, "paymentId"), text(input.reason));
});
export const cancelUnpaidLesson = onCall(options, async (request) => {
  const uid = await authenticated(request); enabled(); return new PaymentLifecycle(db, noGateway).cancelUnpaid(uid, requestId(request.data, "lessonId"));
});
export const completePaidLesson = onCall(options, async (request) => {
  const uid = await authenticated(request); enabled(); const input = object(request.data, ["lessonId", "reviewScore", "reviewFeedback", "signatureMove", "attendanceConfirmed"]);
  if (input.attendanceConfirmed !== true) throw new HttpsError("invalid-argument", "실제 레슨 참여를 확인해 주세요.");
  if (typeof input.reviewFeedback !== "string" || input.reviewFeedback.length > 1000) throw new HttpsError("invalid-argument", "피드백을 확인해 주세요.");
  return new PaymentLifecycle(db, noGateway).complete(uid, documentId(input.lessonId, "lessonId"), input.reviewScore as number, input.reviewFeedback, text(input.signatureMove, 40));
});
export const listPayments = onCall(options, async (request) => {
  const uid = await authenticated(request); const input = object(request.data, ["cursor"]);
  const account = (await db.collection("users").doc(uid).get()).data();
  const admin = account?.role === "admin"; const coach = account?.role === "coach";
  let query: FirebaseFirestore.Query = db.collection("payments");
  if (!admin) query = query.where(coach ? "instructorUid" : "studentUid", "==", uid);
  query = query.orderBy("createdAt", "desc").limit(25);
  if (input.cursor) {
    const cursor = await db.collection("payments").doc(documentId(input.cursor, "cursor")).get();
    if (!cursor.exists || (!admin && cursor.data()?.[coach ? "instructorUid" : "studentUid"] !== uid)) throw new HttpsError("permission-denied", "조회 위치가 올바르지 않습니다.");
    query = query.startAfter(cursor);
  }
  const snapshot = await query.get();
  const lessons = snapshot.empty ? [] : await db.getAll(...snapshot.docs.map((doc) => db.collection("lesson_requests").doc(doc.data().lessonId)));
  return {payments: snapshot.docs.map((doc, index) => ({...projectPayment(doc.data() as PaymentDocument, coach && !admin),
    lessonStatus: lessons[index]?.data()?.status ?? "unknown", instructorName: lessons[index]?.data()?.instructorName ?? "코치", studentName: lessons[index]?.data()?.studentName ?? "수강생",
    refundStatus: doc.data().refundStatus ?? "none"})), nextCursor: snapshot.size === 25 ? snapshot.docs.at(-1)!.id : null};
});
export const getPaymentSummary = onCall(options, async (request) => {
  const uid = await authenticated(request); const user = (await db.collection("users").doc(uid).get()).data();
  if (user?.role !== "admin") throw new HttpsError("permission-denied", "관리자만 매출 지표를 조회할 수 있습니다.");
  const data = (await db.collection("payment_stats").doc("summary").get()).data() ?? {};
  return Object.fromEntries(["paidCount", "grossApprovedAmount", "refundCount", "refundedAmount", "completedLessonCount", "completedAmount", "platformFeeTotal", "coachReadyTotal"].map((key) => [key, data[key] ?? 0]));
});
export const paymentWebhook = onRequest({...secretOptions, timeoutSeconds: 30}, async (request, response) => {
  if (request.method !== "POST") { response.sendStatus(405); return; }
  if (!preparationEnabled.value() || paymentGatewayMode.value() !== "toss-test") { response.status(503).json({code: "WEBHOOK_DISABLED"}); return; }
  try {
    // Public payload only selects a known order. Status/amount are re-fetched
    // from the authenticated PG API using the stored server-side payment key.
    const paymentId = documentId(request.body?.data?.orderId, "orderId");
    await logic().reconcileFromProvider(paymentId); response.status(200).json({received: true});
  } catch (error) {
    logger.warn("payment_webhook_rejected", {code: error instanceof HttpsError ? error.code : "internal"});
    response.status(400).json({code: "VERIFICATION_FAILED"});
  }
});
export const reconcilePendingPayments = onSchedule({...secretOptions, schedule: "every 15 minutes", timeoutSeconds: 120}, async () => {
  if (!preparationEnabled.value() || paymentGatewayMode.value() !== "toss-test") return;
  const pending = await db.collection("payment_gateway_records").where("operation", "in", ["confirming", "refunding"]).limit(50).get();
  for (const record of pending.docs) {
    if (record.data().leaseUntil?.toMillis() > Date.now()) continue;
    try { await logic().reconcileFromProvider(record.id); }
    catch (error) { logger.warn("payment_reconcile_pending", {paymentId: record.id, code: error instanceof HttpsError ? error.code : "internal"}); }
  }
});

export {adminManageAccount, validateCareerPdf} from "./admin_accounts";
export {projectUserPublicProfile, projectInstructorPublicProfile, requestLesson, requestLessonWithSlot, completeLesson, setFeedLiked, deleteVideo} from "./security_workflows";
export {saveAvailabilitySlot, saveAvailabilitySlots, deleteAvailabilitySlot, rescheduleLesson, releaseCancelledSlot, projectPublicAvailability} from "./scheduling";
