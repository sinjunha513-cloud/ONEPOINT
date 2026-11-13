import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config/payment_environment.dart';
import 'lesson_requests_screen.dart';
import 'payment_history_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/lesson_service.dart';
import 'main_screen.dart';

class PaymentDemoScreen extends StatefulWidget {
  const PaymentDemoScreen({super.key});
  @override
  State<PaymentDemoScreen> createState() => _PaymentDemoScreenState();
}

class _PaymentDemoScreenState extends State<PaymentDemoScreen> {
  String? _role;
  bool _busy = false;
  String? _error;
  Future<void> _login(String role) async {
    if (_busy || !paymentDemo) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: '$role@onepoint-demo.test', password: 'onepoint-demo-only');
      if (mounted) setState(() => _role = role);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '체험 서버를 연결하지 못했습니다. 에뮬레이터 실행 상태를 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _requestLesson() async {
    if (_busy || !paymentDemo || _role != 'student') return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LessonService().requestLesson(
          instructorId: 'demo-coach',
          instructorName: '원포인트 체험 코치',
          coachUid: 'demo-coach');
      if (mounted) _open(const LessonRequestsScreen());
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = '이미 진행 중인 새 체험 레슨이 있습니다. 내 레슨에서 먼저 완료하거나 취소해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ONEPOINT · 결제 흐름 체험')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(padding: const EdgeInsets.all(28), children: [
                  const Icon(Icons.bolt, size: 68, color: Color(0xFF38BDF8)),
                  const SizedBox(height: 20),
                  const Text('레슨부터 정산까지,\n직접 확인해 보세요.',
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('체험용 계정과 레슨만 사용합니다.\n실제 결제·운영 회원 변경·계좌 지급은 없습니다.',
                      style:
                          TextStyle(color: Colors.orangeAccent, height: 1.7)),
                  const SizedBox(height: 24),
                  const Card(
                      color: Color(0xFF1A1C29),
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('확인 순서',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                                SizedBox(height: 12),
                                Text(
                                    '1. 코치로 접속 → 신청 수락 및 금액 입력\n2. 수강생으로 접속 → 레슨 결제·예약 확정\n3. 코치로 접속 → 실제 참여 확인 및 레슨 완료\n4. 관리자 / 코치 → 수수료·정산 예정액 확인\n5. 다른 샘플 레슨으로 전액·부분 환불 확인',
                                    style: TextStyle(height: 1.8)),
                              ]))),
                  const SizedBox(height: 24),
                  for (final entry in {
                    'student': '수강생으로 체험',
                    'coach': '코치로 체험',
                    'admin': '관리자로 체험'
                  }.entries)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton(
                            onPressed: _busy ? null : () => _login(entry.key),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                    '${entry.value}${_role == entry.key ? ' · 접속 중' : ''}')))),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Text(_error!,
                        style: const TextStyle(color: Colors.orangeAccent)),
                  if (_role != null && !_busy) ...[
                    TextButton(
                        onPressed: () => _open(const MainScreen()),
                        child: const Text('홈 종목 · 코치 보기')),
                    if (_role == 'student')
                      TextButton(
                          onPressed: _requestLesson,
                          child: const Text('신규 체험 레슨 신청')),
                    const SizedBox(height: 20),
                    if (_role != 'admin')
                      FilledButton(
                          onPressed: () => _open(const LessonRequestsScreen()),
                          child: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('내 레슨 확인'))),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () => _open(PaymentHistoryScreen(
                            adminMode: _role == 'admin',
                            coachMode: _role == 'coach')),
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(_role == 'admin'
                                ? '결제 관리·매출 지표'
                                : _role == 'coach'
                                    ? '정산 예정 내역'
                                    : '나의 결제 내역'))),
                    if (_role == 'admin')
                      TextButton(
                          onPressed: () => _open(const AdminDashboardScreen()),
                          child: const Text('회원·코치 관리도 확인하기')),
                  ],
                ]))),
      );
}
