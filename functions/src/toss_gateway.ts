import {HttpsError} from "firebase-functions/v2/https";
import {assertTestSecret} from "./config";
import {ConfirmRequest, CancelRequest} from "./gateway";
import {Firestore} from "firebase-admin/firestore";

export interface GatewayPayment {
  paymentKey: string; providerOrderId: string; amount: number; currency: "KRW";
  status: "DONE" | "CANCELED" | "PARTIAL_CANCELED"; balanceAmount: number; paymentMethod: string;
}
export interface Gateway {
  confirm(request: ConfirmRequest): Promise<GatewayPayment>;
  cancel(request: CancelRequest): Promise<GatewayPayment>;
  get(paymentKey: string): Promise<GatewayPayment>;
}

function validated(data: Record<string, unknown>): GatewayPayment {
  if (["READY", "IN_PROGRESS", "WAITING_FOR_DEPOSIT", "ABORTED", "EXPIRED"].includes(data.status as string)) {
    throw new HttpsError("failed-precondition", "PG 결제 승인이 완료되지 않았습니다.");
  }
  if (typeof data.paymentKey !== "string" || typeof data.orderId !== "string" ||
      data.currency !== "KRW" || !Number.isSafeInteger(data.totalAmount) ||
      !Number.isSafeInteger(data.balanceAmount) || (data.balanceAmount as number) < 0 ||
      (data.balanceAmount as number) > (data.totalAmount as number) ||
      !["DONE", "CANCELED", "PARTIAL_CANCELED"].includes(data.status as string)) {
    throw new HttpsError("data-loss", "PG 응답 검증에 실패했습니다. 관리자 확인이 필요합니다.");
  }
  return {paymentKey: data.paymentKey, providerOrderId: data.orderId,
    amount: data.totalAmount as number, balanceAmount: data.balanceAmount as number,
    currency: "KRW", status: data.status as GatewayPayment["status"],
    paymentMethod: typeof data.method === "string" ? data.method : "카드"};
}

export class TossTestGateway implements Gateway {
  constructor(private readonly secret: string, private readonly transport: typeof fetch = fetch) {
    assertTestSecret(secret);
  }
  private async api(path: string, body?: Record<string, unknown>, idempotencyKey?: string): Promise<GatewayPayment> {
    let response: Response;
    try {
      response = await this.transport(`https://api.tosspayments.com/v1/payments${path}`, {
        method: body ? "POST" : "GET",
        headers: {Authorization: `Basic ${Buffer.from(`${this.secret}:`).toString("base64")}`,
          "Content-Type": "application/json", ...(idempotencyKey ? {"Idempotency-Key": idempotencyKey} : {})},
        ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(15000),
      });
    } catch { throw new HttpsError("unavailable", "PG 응답을 확인하지 못했습니다. 결제 내역에서 다시 확인해 주세요."); }
    if (!response.ok) {
      // Never return or log the raw PG response (may contain sensitive data).
      throw new HttpsError(response.status >= 500 || response.status === 429 ? "unavailable" : "failed-precondition",
        "PG 요청을 처리하지 못했습니다. 결제 내역에서 상태를 다시 확인해 주세요.");
    }
    let data: Record<string, unknown>;
    try { data = await response.json() as Record<string, unknown>; }
    catch { throw new HttpsError("data-loss", "PG 응답 형식이 올바르지 않습니다."); }
    return validated(data);
  }
  async confirm(request: ConfirmRequest) {
    // Replays first look up the same payment. An already approved payment is
    // reconciled without sending another approval request.
    try { return await this.get(request.paymentKey); }
    catch (error) {
      if (!(error instanceof HttpsError) || error.code !== "failed-precondition") throw error;
    }
    return this.api("/confirm", {paymentKey: request.paymentKey, orderId: request.providerOrderId, amount: request.amount}, request.idempotencyKey);
  }
  cancel(request: CancelRequest) {
    return this.api(`/${encodeURIComponent(request.paymentKey)}/cancel`, {
      cancelReason: request.reason, cancelAmount: request.amount,
    }, request.idempotencyKey);
  }
  get(paymentKey: string) { return this.api(`/${encodeURIComponent(paymentKey)}`); }
}

/** In-memory PG simulator. It can only be constructed for isolated demo emulators. */
export class DemoGateway implements Gateway {
  private payments = new Map<string, GatewayPayment>();
  private results = new Map<string, GatewayPayment>();
  constructor(env: NodeJS.ProcessEnv = process.env, private readonly db?: Firestore) {
    if (env.FUNCTIONS_EMULATOR !== "true" || !env.FIRESTORE_EMULATOR_HOST ||
        !env.FIREBASE_AUTH_EMULATOR_HOST || !env.GCLOUD_PROJECT?.startsWith("demo-")) {
      throw new HttpsError("failed-precondition", "체험 결제는 별도 demo 에뮬레이터에서만 가능합니다.");
    }
  }
  async confirm(request: ConfirmRequest): Promise<GatewayPayment> {
    if (request.paymentKey !== `demo_${request.paymentId}`) {
      throw new HttpsError("failed-precondition", "체험 결제 인증값이 일치하지 않습니다.");
    }
    const prior = this.payments.get(request.paymentKey);
    if (prior) return prior;
    const payment: GatewayPayment = {paymentKey: request.paymentKey, providerOrderId: request.providerOrderId,
      amount: request.amount, balanceAmount: request.amount, currency: "KRW", status: "DONE", paymentMethod: "체험 카드 · 실제 결제 없음"};
    if (this.db) {
      const ref = this.db.collection("demo_gateway_payments").doc(request.paymentKey);
      return this.db.runTransaction(async (tx) => {
        const prior = (await tx.get(ref)).data() as GatewayPayment | undefined;
        if (prior) return prior;
        tx.create(ref, payment); return payment;
      });
    }
    this.payments.set(request.paymentKey, payment);
    return payment;
  }
  async cancel(request: CancelRequest) {
    if (this.db) {
      const ref = this.db.collection("demo_gateway_payments").doc(request.paymentKey);
      const operation = this.db.collection("demo_gateway_operations").doc(request.idempotencyKey);
      return this.db.runTransaction(async (tx) => {
        const payment = (await tx.get(ref)).data() as GatewayPayment | undefined;
        const prior = (await tx.get(operation)).data() as GatewayPayment | undefined;
        if (prior) return prior;
        if (!payment || request.amount <= 0 || request.amount > payment.balanceAmount) throw new HttpsError("failed-precondition", "체험 환불 잔액을 확인해 주세요.");
        const balanceAmount = payment.balanceAmount - request.amount;
        const result: GatewayPayment = {...payment, balanceAmount, status: balanceAmount === 0 ? "CANCELED" : "PARTIAL_CANCELED"};
        tx.set(ref, result); tx.create(operation, result); return result;
      });
    }
    const prior = this.results.get(request.idempotencyKey); if (prior) return prior;
    const payment = await this.get(request.paymentKey);
    if (request.amount <= 0 || request.amount > payment.balanceAmount) throw new HttpsError("failed-precondition", "환불 금액이 잔액을 초과했습니다.");
    const balanceAmount = payment.balanceAmount - request.amount;
    const result: GatewayPayment = {...payment, balanceAmount, status: balanceAmount === 0 ? "CANCELED" : "PARTIAL_CANCELED"};
    this.payments.set(request.paymentKey, result); this.results.set(request.idempotencyKey, result);
    return result;
  }
  async get(key: string) {
    const payment = this.db ? (await this.db.collection("demo_gateway_payments").doc(key).get()).data() as GatewayPayment | undefined : this.payments.get(key);
    if (!payment) throw new HttpsError("failed-precondition", "PG 기록이 없습니다.");
    return payment;
  }
}
