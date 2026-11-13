import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/payment_environment.dart';
import '../services/payment_service.dart';

class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen(
      {super.key,
      required this.lessonId,
      required this.instructorName,
      this.service});
  final String lessonId;
  final String instructorName;
  final PaymentService? service;
  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  late final _service = widget.service ?? PaymentService();
  Map<String, dynamic>? _payment;
  String? _error;
  bool _busy = false;
  bool _paid = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _service.isPaymentTestEnabled()) {
        throw StateError(
          '결제 테스트 연동 준비 중입니다. 토스페이먼츠 테스트 상점 키 등록 후 이용할 수 있습니다.',
        );
      }
      final payment = await _service.prepare(widget.lessonId);
      if (mounted) setState(() => _payment = payment);
    } catch (error) {
      if (mounted) setState(() => _error = paymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    if (_busy || _payment == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (paymentDemo) {
        await _service.confirm(
            _payment!['paymentId'] as String, 'demo_${_payment!['paymentId']}');
        if (mounted) setState(() => _paid = true);
      } else {
        final url = _service.checkoutUrl(_payment!, mobile: !kIsWeb);
        if (!await launchUrl(url,
            mode: kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication,
            webOnlyWindowName: '_self')) {
          throw StateError('결제창을 열지 못했습니다. 다시 시도해 주세요.');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = paymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_paid ? '예약 확정' : '레슨 결제')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  if (paymentDemo)
                    const Card(
                        color: Color(0xFF1A1C29),
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                '결제 화면 체험 · 실제 결제 없음\n운영 회원·레슨과 분리된 테스트 공간입니다.'))),
                  const SizedBox(height: 24),
                  Icon(_paid ? Icons.check_circle_outline : Icons.sports_soccer,
                      color: const Color(0xFF38BDF8), size: 64),
                  const SizedBox(height: 20),
                  Text(
                      _paid
                          ? '결제가 확인되어 예약이 확정됐어요.'
                          : '${widget.instructorName} 코치와의 원포인트 레슨',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  if (_payment != null)
                    Card(
                        color: const Color(0xFF1A1C29),
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('레슨 금액',
                                      style: TextStyle(color: Colors.white60)),
                                  const SizedBox(height: 8),
                                  Text(
                                      '${NumberFormat('#,###').format(_payment!['amount'])}원',
                                      style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  const Text(
                                      '서버에서 확인한 레슨 금액입니다. 결제 후 예약이 확정됩니다.',
                                      style: TextStyle(color: Colors.white60)),
                                ]))),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(_error!,
                            style:
                                const TextStyle(color: Colors.orangeAccent))),
                  const SizedBox(height: 24),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else if (_paid)
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('내 레슨으로 돌아가기'))
                  else if (_payment != null)
                    FilledButton(
                        onPressed: _pay,
                        child: const Text(
                            paymentDemo ? '체험 결제 확인하기' : '토스 테스트 결제하기'))
                  else
                    FilledButton(onPressed: _load, child: const Text('다시 확인')),
                  const SizedBox(height: 16),
                  const Text('결제 완료와 레슨 완료는 별개입니다. 실제 레슨 참여 후 코치가 완료를 확인합니다.',
                      style: TextStyle(color: Colors.white54)),
                ]))),
      );
}
