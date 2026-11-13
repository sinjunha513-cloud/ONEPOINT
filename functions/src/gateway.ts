import {HttpsError} from "firebase-functions/v2/https";

// STEP 5 implements this boundary against the current official Toss API.
// These interfaces are contracts, not an SDK or a simulated approval service.
export interface ConfirmRequest { paymentId: string; paymentKey: string; providerOrderId: string; amount: number; idempotencyKey: string; }
export interface VerifiedPayment { paymentKey: string; providerOrderId: string; amount: number; currency: "KRW"; status: "DONE"; paymentMethod: string; }
export interface CancelRequest { paymentId: string; paymentKey: string; amount: number; reason: string; idempotencyKey: string; }
export interface VerifiedCancellation { amount: number; providerTransactionId: string; }
export interface PaymentGateway {
  confirm(request: ConfirmRequest): Promise<VerifiedPayment>;
  cancel(request: CancelRequest): Promise<VerifiedCancellation>;
}
export class UnconnectedGateway implements PaymentGateway {
  async confirm(_request: ConfirmRequest): Promise<VerifiedPayment> {
    throw new HttpsError("unimplemented", "Test PG confirmation is not connected in STEP 4.");
  }
  async cancel(_request: CancelRequest): Promise<VerifiedCancellation> {
    throw new HttpsError("unimplemented", "Test PG cancellation is not connected in STEP 4.");
  }
}
