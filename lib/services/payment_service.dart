import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/payment_environment.dart';

class PaymentService {
  PaymentService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions,
        _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFunctions? _functions;
  final FirebaseFirestore _firestore;
  FirebaseFunctions get _api =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> data) async {
    final result = await _api.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> prepare(String lessonId) =>
      call('preparePayment', {'lessonId': lessonId});
  Future<Map<String, dynamic>> status(String paymentId) =>
      call('getPaymentStatus', {'paymentId': paymentId});
  Future<Map<String, dynamic>> list({String? cursor}) =>
      call('listPayments', {if (cursor != null) 'cursor': cursor});
  Future<Map<String, dynamic>> summary() => call('getPaymentSummary', {});

  Future<bool> isPaymentTestEnabled() async {
    if (paymentDemo) return true;
    final config =
        await _firestore.collection('app_config').doc('features').get();
    return config.data()?['paymentTestEnabled'] == true;
  }

  Future<Map<String, dynamic>> confirm(String paymentId, String paymentKey) =>
      call(
          'confirmPayment', {'paymentId': paymentId, 'paymentKey': paymentKey});
  Future<Map<String, dynamic>> reconcile(String paymentId) =>
      call('reconcilePayment', {'paymentId': paymentId});
  Future<void> accept(String lessonId, int price) async {
    await call('acceptPaidLesson', {'lessonId': lessonId, 'price': price});
  }

  Future<void> complete(
      String lessonId, double score, String feedback, String signature) async {
    await call('completePaidLesson', {
      'lessonId': lessonId,
      'reviewScore': score,
      'reviewFeedback': feedback,
      'signatureMove': signature,
      'attendanceConfirmed': true
    });
  }

  Future<void> cancelUnpaid(String lessonId) async {
    await call('cancelUnpaidLesson', {'lessonId': lessonId});
  }

  Future<void> requestRefund(String paymentId, String reason) async {
    await call(
        'requestPaymentRefund', {'paymentId': paymentId, 'reason': reason});
  }

  Future<void> refund(String paymentId, String operationId, String reason,
      {int? amount}) async {
    await call('cancelPayment', {
      'paymentId': paymentId,
      'refundId': operationId,
      'reason': reason,
      if (amount != null) 'amount': amount
    });
  }

  Uri checkoutUrl(Map<String, dynamic> payment, {required bool mobile}) {
    final key = payment['clientKey'] as String? ?? '';
    if (!key.startsWith('test_ck_') && !key.startsWith('test_gck_')) {
      throw StateError('토스 테스트 Client Key 등록이 필요합니다.');
    }
    final configured = payment['checkoutBaseUrl'] as String? ?? '';
    final base = configured.isEmpty ? Uri.base.origin : configured;
    final root = Uri.tryParse(base);
    if (root == null || (!paymentDemo && root.scheme != 'https')) {
      throw StateError('HTTPS 결제 페이지 주소 설정이 필요합니다.');
    }
    return root.resolve('/payment-checkout.html').replace(queryParameters: {
      'paymentId': payment['paymentId'] as String,
      'orderId': payment['providerOrderId'] as String,
      'amount': '${payment['amount']}',
      'clientKey': key,
      'customerKey': payment['customerKey'] as String,
      if (mobile) 'mobile': '1',
    });
  }
}

String paymentError(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message ?? '';
    if (error.code == 'not-found' || error.code == 'unimplemented') {
      return '결제 테스트 연동 전입니다. 토스페이먼츠 테스트 상점 키를 등록한 뒤 결제 서버를 배포해야 합니다.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return '결제 상태를 확인하지 못했습니다. 중복 결제하지 말고 내역에서 다시 확인해 주세요.';
    }
    final genericMessage = message.contains('요청을 처리하지 못') ||
        message.contains('처리하지 못했습니다') ||
        message.trim().toLowerCase() == 'internal';
    if (!genericMessage && RegExp(r'[가-힣]').hasMatch(message)) return message;
    return switch (error.code) {
      'internal' ||
      'unknown' =>
        '결제 서버를 사용할 수 없습니다. 토스 테스트 키와 Functions 배포 상태를 확인해 주세요.',
      'unauthenticated' => '로그인한 뒤 다시 시도해 주세요.',
      'permission-denied' => '이 결제 또는 레슨을 처리할 권한이 없습니다.',
      'failed-precondition' => '레슨 수락·금액·결제 상태를 먼저 확인해 주세요.',
      'invalid-argument' => '입력한 결제 정보를 확인해 주세요.',
      'aborted' => '결제 처리가 진행 중입니다. 잠시 후 내역을 다시 확인해 주세요.',
      'data-loss' => 'PG 결제 정보 검증에 실패했습니다. 관리자에게 문의해 주세요.',
      _ => '요청을 처리하지 못했습니다. 내역에서 상태를 다시 확인해 주세요.',
    };
  }
  if (error is StateError) return error.message.toString();
  return '처리하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.';
}
