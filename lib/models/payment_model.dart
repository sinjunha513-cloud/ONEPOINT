import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus {
  pending,
  paid,
  failed,
  cancelled,
  refunded,
  partialRefunded,
  unknown
}

enum PayoutStatus { pending, ready, completed, held, cancelled, unknown }

/// Read-only DTO for server-issued payment views. There is deliberately no
/// toMap/save method or provider secret/payment-key field.
class PaymentModel {
  const PaymentModel({
    required this.paymentId,
    required this.lessonId,
    required this.instructorUid,
    required this.amount,
    required this.currency,
    required this.platformFeeBps,
    required this.platformFee,
    required this.coachAmount,
    required this.paymentStatus,
    required this.payoutStatus,
    required this.refundedAmount,
    this.studentUid,
    this.providerOrderId,
    this.paymentMethod,
    this.createdAt,
    this.paidAt,
    this.cancelledAt,
    this.refundedAt,
  });

  final String paymentId;
  final String lessonId;
  final String instructorUid;
  final String? studentUid;
  final int amount;
  final String currency;
  final int platformFeeBps;
  final int platformFee;
  final int coachAmount;
  final PaymentStatus paymentStatus;
  final PayoutStatus payoutStatus;
  final int refundedAmount;
  final String? providerOrderId;
  final String? paymentMethod;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final DateTime? refundedAt;

  factory PaymentModel.fromMap(Map<String, dynamic> data) {
    if (data['schemaVersion'] != 1 || data['currency'] != 'KRW') {
      throw const FormatException('지원하지 않는 결제 데이터 형식입니다.');
    }
    final amount = _integer(data, 'amount');
    final fee = _integer(data, 'platformFee');
    final coachAmount = _integer(data, 'coachAmount');
    final bps = _integer(data, 'platformFeeBps');
    final refunded = _integer(data, 'refundedAmount');
    if (amount <= 0 ||
        fee + coachAmount != amount ||
        bps > 10000 ||
        refunded > amount) {
      throw const FormatException('결제 금액 정보가 올바르지 않습니다.');
    }
    return PaymentModel(
      paymentId: _requiredText(data, 'paymentId'),
      lessonId: _requiredText(data, 'lessonId'),
      instructorUid: _requiredText(data, 'instructorUid'),
      studentUid: data['studentUid'] as String?,
      amount: amount,
      currency: 'KRW',
      platformFeeBps: bps,
      platformFee: fee,
      coachAmount: coachAmount,
      refundedAmount: refunded,
      paymentStatus: switch (data['paymentStatus']) {
        'pending' => PaymentStatus.pending,
        'paid' => PaymentStatus.paid,
        'failed' => PaymentStatus.failed,
        'cancelled' => PaymentStatus.cancelled,
        'refunded' => PaymentStatus.refunded,
        'partial_refunded' => PaymentStatus.partialRefunded,
        _ => PaymentStatus.unknown,
      },
      payoutStatus: switch (data['payoutStatus']) {
        'pending' => PayoutStatus.pending,
        'ready' => PayoutStatus.ready,
        'completed' => PayoutStatus.completed,
        'held' => PayoutStatus.held,
        'cancelled' => PayoutStatus.cancelled,
        _ => PayoutStatus.unknown,
      },
      providerOrderId: data['providerOrderId'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      createdAt: _date(data['createdAt']),
      paidAt: _date(data['paidAt']),
      cancelledAt: _date(data['cancelledAt']),
      refundedAt: _date(data['refundedAt']),
    );
  }

  static int _integer(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value > 9007199254740991 ||
        value != value.truncateToDouble()) {
      throw FormatException('유효한 정수 금액이 필요합니다: $key');
    }
    return value.toInt();
  }

  static String _requiredText(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('필수 결제 정보 누락: $key');
    }
    return value;
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null) return date;
    }
    throw const FormatException('유효하지 않은 결제 시각입니다.');
  }
}
