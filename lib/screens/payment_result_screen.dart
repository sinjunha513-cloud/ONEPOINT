import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/payment_service.dart';
import 'payment_history_screen.dart';

class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({super.key, required this.parameters});
  final Map<String, String> parameters;
  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.parameters['code'] != null) {
        throw StateError('결제가 완료되지 않았습니다. 내 레슨에서 다시 시도해 주세요.');
      }
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) {
        throw StateError('결제한 계정으로 다시 로그인한 뒤 결제 내역에서 상태를 확인해 주세요.');
      }
      final paymentId = widget.parameters['paymentId'];
      final key = widget.parameters['paymentKey'];
      if (paymentId == null || key == null) throw StateError('결제 결과 정보가 없습니다.');
      final api = PaymentService();
      final payment = await api.status(paymentId);
      if (widget.parameters['orderId'] != payment['providerOrderId'] ||
          int.tryParse(widget.parameters['amount'] ?? '') !=
              payment['amount']) {
        throw StateError('결제 결과 금액과 주문이 일치하지 않습니다. 관리자에게 문의해 주세요.');
      }
      await api.confirm(paymentId, key);
    } catch (error) {
      if (mounted) setState(() => _error = paymentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('결제 결과 확인')),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_busy)
                    const CircularProgressIndicator()
                  else ...[
                    Icon(
                        _error == null
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 60,
                        color: const Color(0xFF38BDF8)),
                    const SizedBox(height: 24),
                    Text(_error ?? '결제 확인 완료 · 예약이 확정됐어요.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PaymentHistoryScreen())),
                        child: const Text('결제 내역 확인')),
                    if (_error != null)
                      TextButton(
                          onPressed: _verify, child: const Text('다시 확인')),
                  ],
                ]))),
      );
}
