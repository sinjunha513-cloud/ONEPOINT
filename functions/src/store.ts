import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {AccountDocument, InstructorDocument, LessonDocument, PaymentDocument} from "./models";

export interface PaymentTransaction {
  lesson(id: string): Promise<LessonDocument | undefined>;
  account(uid: string): Promise<AccountDocument | undefined>;
  instructor(uid: string): Promise<InstructorDocument | undefined>;
  payment(id: string): Promise<PaymentDocument | undefined>;
  createPayment(id: string, data: PaymentDocument): void;
  linkLesson(id: string, paymentId: string): void;
}
export interface PaymentStore {
  lesson?(id: string): Promise<LessonDocument | undefined>;
  transaction<T>(work: (transaction: PaymentTransaction) => Promise<T>): Promise<T>;
  payment(id: string): Promise<PaymentDocument | undefined>;
  account(uid: string): Promise<AccountDocument | undefined>;
  now(): Timestamp | FieldValue;
}

export class FirestorePaymentStore implements PaymentStore {
  constructor(private readonly db: Firestore) {}
  now() { return FieldValue.serverTimestamp(); }
  async lesson(id: string) {
    return (await this.db.collection("lesson_requests").doc(id).get()).data() as LessonDocument | undefined;
  }
  async payment(id: string) {
    return (await this.db.collection("payments").doc(id).get()).data() as PaymentDocument | undefined;
  }
  async account(uid: string) {
    return (await this.db.collection("users").doc(uid).get()).data() as AccountDocument | undefined;
  }
  transaction<T>(work: (transaction: PaymentTransaction) => Promise<T>): Promise<T> {
    return this.db.runTransaction(async (transaction) => work({
      lesson: async (id) => (await transaction.get(this.db.collection("lesson_requests").doc(id))).data() as LessonDocument | undefined,
      account: async (uid) => (await transaction.get(this.db.collection("users").doc(uid))).data() as AccountDocument | undefined,
      instructor: async (uid) => (await transaction.get(this.db.collection("instructors").doc(uid))).data() as InstructorDocument | undefined,
      payment: async (id) => (await transaction.get(this.db.collection("payments").doc(id))).data() as PaymentDocument | undefined,
      createPayment: (id, data) => { transaction.create(this.db.collection("payments").doc(id), data); },
      linkLesson: (id, paymentId) => { transaction.update(this.db.collection("lesson_requests").doc(id), {
        paymentId, paymentStatus: "pending", updatedAt: FieldValue.serverTimestamp(),
      }); },
    }));
  }
}
