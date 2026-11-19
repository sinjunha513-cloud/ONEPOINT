import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';
import '../services/coupon_service.dart';

class CouponWalletScreen extends StatefulWidget {
  const CouponWalletScreen({super.key, this.service, this.lessonId});
  final CouponService? service;
  final String? lessonId;
  @override
  State<CouponWalletScreen> createState() => _CouponWalletScreenState();
}

class _CouponWalletScreenState extends State<CouponWalletScreen> {
  late final _service = widget.service ?? CouponService();
  late final _coupons = _service.coupons();
  late final _eligible = _service.eligible();
  String? _applying;
  Future<void> _apply(String id) async {
    if (_applying != null || widget.lessonId == null) return;
    setState(() => _applying = id);
    try {
      await _service.apply(widget.lessonId!, id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(couponError(error))));
      }
    } finally {
      if (mounted) setState(() => _applying = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.lessonId == null ? '내 할인권' : '할인권 선택')),
      body: StreamBuilder<bool>(
          stream: _eligible,
          builder: (context, eligibility) {
            if (eligibility.hasError) {
              return const Center(child: Text('수강생 계정 정보를 확인하지 못했습니다.'));
            }
            if (!eligibility.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (eligibility.data != true) {
              return const Center(child: Text('할인권은 수강생 전용입니다.'));
            }
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _coupons,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                                child: Text('할인권을 불러오지 못했습니다. 다시 시도해 주세요.'));
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final docs = [...snapshot.data!.docs]
                            ..sort((a, b) => b.id.compareTo(a.id));
                          return ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                const Text('매달 레슨 20회 수강 완료',
                                    style: OnepointDesign.heading),
                                const SizedBox(height: 8),
                                const Text(
                                    '수강생 전용 혜택이에요. 월 20회 수강을 완료하면 월 1회, 다음 유료 레슨 1건에 10% 할인을 받을 수 있어요.\n받은 날부터 30일 이내에 적용해 주세요.',
                                    style: TextStyle(
                                        color: OnepointDesign.muted,
                                        height: 1.6)),
                                const SizedBox(height: 24),
                                if (docs.isEmpty)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 48),
                                      child: Text(
                                          '아직 받은 할인권이 없어요.\n홈에서 이번 달 목표를 달성하고 받아보세요.',
                                          textAlign: TextAlign.center)),
                                for (final doc in docs) _coupon(doc),
                              ]);
                        })));
          }));

  Widget _coupon(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final expiry = data['expiresAt'] is Timestamp
        ? (data['expiresAt'] as Timestamp)
            .toDate()
            .toUtc()
            .add(const Duration(hours: 9))
        : null;
    final expired = expiry == null ||
        !(data['expiresAt'] as Timestamp).toDate().isAfter(DateTime.now());
    final status = data['status'];
    final available = status == 'available' && !expired;
    final label = status == 'used'
        ? '사용 완료'
        : status == 'reserved'
            ? '레슨에 적용 중'
            : expired || status == 'expired'
                ? '기간 만료'
                : '사용 가능';
    final month = data['earnedMonth'] as String? ?? '';
    return Card(
        key: ValueKey('coupon-${doc.id}'),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.local_offer_outlined,
                    color:
                        available ? OnepointDesign.lime : OnepointDesign.muted),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('월간 목표 달성 할인권', style: OnepointDesign.heading)),
              ]),
              const SizedBox(height: 18),
              Text('10% OFF',
                  style: TextStyle(
                      color: available
                          ? OnepointDesign.lime
                          : OnepointDesign.muted,
                      fontSize: 34,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (month.length == 6)
                Text(
                    '${month.substring(0, 4)}년 ${int.tryParse(month.substring(4)) ?? ''}월 목표 달성'),
              const SizedBox(height: 6),
              Text(
                  expiry == null
                      ? '사용 기한 확인 필요'
                      : '${expiry.year}.${expiry.month.toString().padLeft(2, '0')}.${expiry.day.toString().padLeft(2, '0')} ${expiry.hour.toString().padLeft(2, '0')}:${expiry.minute.toString().padLeft(2, '0')}까지 (한국 시간)',
                  style: const TextStyle(
                      color: OnepointDesign.muted, fontSize: 12)),
              const SizedBox(height: 12),
              Text(label,
                  style: TextStyle(
                      color: available
                          ? OnepointDesign.lime
                          : OnepointDesign.muted)),
              if (status == 'reserved')
                const Text('내 레슨에서 확인할 수 있어요. 결제 준비 전에는 해제 후 다시 선택할 수 있어요.',
                    style:
                        TextStyle(color: OnepointDesign.muted, fontSize: 12)),
              if (widget.lessonId != null && available) ...[
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed:
                            _applying != null ? null : () => _apply(doc.id),
                        child:
                            Text(_applying == doc.id ? '적용 중…' : '이 레슨에 적용'))),
              ] else if (widget.lessonId == null && available)
                const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('내 레슨 → 결제 전 할인권 적용',
                        style: TextStyle(
                            color: OnepointDesign.muted, fontSize: 12))),
            ])));
  }
}
