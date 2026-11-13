import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/payment_service.dart';

void main() {
  test(
      'missing payment backend is explained instead of shown as a generic error',
      () {
    expect(
      paymentError(FirebaseFunctionsException(
        code: 'internal',
        message: 'internal',
      )),
      contains('Functions 배포'),
    );
    expect(
      paymentError(FirebaseFunctionsException(
        code: 'not-found',
        message: '요청을 처리하지 못했습니다.',
      )),
      contains('결제 테스트 연동 전입니다'),
    );
  });

  test('payment feature stays disabled until an administrator enables it',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = PaymentService(firestore: firestore);

    expect(await service.isPaymentTestEnabled(), isFalse);
    await firestore.collection('app_config').doc('features').set({
      'paymentTestEnabled': true,
    });
    expect(await service.isPaymentTestEnabled(), isTrue);
  });
}
