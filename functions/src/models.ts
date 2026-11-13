import {FieldValue, Timestamp} from "firebase-admin/firestore";
export const supportedSports = [
  "축구", "농구", "테니스", "배드민턴", "클라이밍", "수영", "골프", "복싱", "유도", "주짓수",
  "태권도", "필라테스", "요가", "탁구", "댄스", "크로스핏", "피겨", "스키", "헬스",
] as const;

export type LessonStatus = "pending" | "accepted" | "rejected" | "confirmed" | "completed" | "cancelled";
export type PaymentStatus = "pending" | "paid" | "failed" | "cancelled" | "refunded" | "partial_refunded";
export type PayoutStatus = "pending" | "ready" | "completed" | "held" | "cancelled";
export type ServerTime = Timestamp | FieldValue;

// The existing status/studentUid/instructorUid names are deliberately retained.
export interface LessonDocument {
  status: LessonStatus;
  paymentRequired?: boolean;
  studentUid: string;
  instructorUid: string;
  participantIds: string[];
  instructorName?: string;
  studentName?: string;
  signatureMove?: string;
  signatureBadgeId?: string;
  signatureBadgeColorIndex?: number;
  price?: number; // Reserved server-owned KRW price; absent in current lessons.
  currency?: "KRW";
  paymentId?: string;
  paymentStatus?: PaymentStatus;
}

export interface PaymentDocument {
  schemaVersion: 1;
  paymentId: string;
  lessonId: string;
  studentUid: string;
  instructorUid: string;
  amount: number;
  currency: "KRW";
  platformFeeBps: number;
  platformFeeRate: number; // Reporting only; arithmetic uses integer BPS.
  platformFee: number;
  coachAmount: number;
  paymentStatus: PaymentStatus;
  payoutStatus: PayoutStatus;
  provider: "toss" | "demo";
  mode: "test" | "demo";
  providerOrderId: string;
  paymentMethod: string | null;
  refundedAmount: number;
  refundStatus?: "none" | "requested" | "processed";
  netPlatformFee?: number;
  netCoachAmount?: number;
  createdAt: ServerTime;
  updatedAt: ServerTime;
  paidAt: ServerTime | null;
  cancelledAt: ServerTime | null;
  refundedAt: ServerTime | null;
}

// Never expose this record through a callable or client-readable document.
// It contains provider references, NOT card/CVC data or a Secret Key.
export interface PaymentGatewayRecord {
  paymentId: string;
  providerPaymentKey: string;
  confirmationIdempotencyKey: string;
  lastVerifiedAt: ServerTime;
}

export interface RefundRecord {
  refundId: string;
  paymentId: string;
  amount: number;
  reason: string;
  requestedBy: string;
  status: "pending" | "succeeded" | "failed";
  idempotencyKey: string;
  createdAt: ServerTime;
  refundedAt: ServerTime | null;
}

export interface AccountDocument { role: string; profileCompleted?: boolean; }
export interface InstructorDocument { status: string; uid: string; userId: string; }
export interface FeePolicy { platformFeeBps: number; }
