import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/models/payment_model.dart';

Map<String, dynamic> payment() => {
      'schemaVersion': 1,
      'paymentId': 'payment',
      'lessonId': 'lesson',
      'studentUid': 'student',
      'instructorUid': 'coach',
      'currency': 'KRW',
      'amount': 50000,
      'platformFeeBps': 1200,
      'platformFee': 6000,
      'coachAmount': 44000,
      'refundedAmount': 0,
      'paymentStatus': 'pending',
      'payoutStatus': 'pending',
      'createdAt': '2026-10-08T00:00:00.000Z',
    };

void main() {
  test('server payment projection retains integer money and pending states',
      () {
    final model = PaymentModel.fromMap(payment());
    expect(model.amount, 50000);
    expect(model.platformFee, 6000);
    expect(model.coachAmount, 44000);
    expect(model.paymentStatus, PaymentStatus.pending);
    expect(model.payoutStatus, PayoutStatus.pending);
    expect(model.paidAt, null);
    expect(model.createdAt!.isUtc, true);
  });
  test('coach projection can omit student and provider references', () {
    final data = payment()..remove('studentUid');
    final model = PaymentModel.fromMap(data);
    expect(model.studentUid, null);
    expect(model.providerOrderId, null);
  });
  test('unknown statuses never imply payment or payout completion', () {
    final model = PaymentModel.fromMap(
        {...payment(), 'paymentStatus': 'success', 'payoutStatus': 'done'});
    expect(model.paymentStatus, PaymentStatus.unknown);
    expect(model.payoutStatus, PayoutStatus.unknown);
  });
  test('invalid prices or fee totals are rejected', () {
    for (final updates in [
      {'amount': 100},
      {'amount': 1.5},
      {'amount': -1},
      {'platformFeeBps': 10001},
      {'currency': 'USD'},
      {'refundedAmount': 60000},
      {'schemaVersion': 2},
    ]) {
      expect(() => PaymentModel.fromMap({...payment(), ...updates}),
          throwsFormatException);
    }
  });
  test('Firestore timestamps and null dates are supported', () {
    final model = PaymentModel.fromMap(
        {...payment(), 'createdAt': Timestamp.fromMillisecondsSinceEpoch(0)});
    expect(model.createdAt!.millisecondsSinceEpoch, 0);
    expect(model.refundedAt, null);
    expect(() => PaymentModel.fromMap({...payment(), 'createdAt': 'invalid'}),
        throwsFormatException);
  });
}
