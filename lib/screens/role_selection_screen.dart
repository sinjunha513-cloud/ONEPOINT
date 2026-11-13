import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'session_gate_screen.dart';
import 'signup_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    this.completeProfile = false,
    this.service,
    this.homeBuilder,
  });

  final bool completeProfile;
  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _signingOut = false;

  Future<void> _switchAccount() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    final service = widget.service ?? AuthService();
    try {
      await service.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SessionGateScreen(
              service: service, homeBuilder: widget.homeBuilder),
        ),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정을 변경하지 못했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('가입 유형 선택',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '원포인트에서 어떤 역할을\n하고 싶으신가요?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.4),
            ),
            const SizedBox(height: 40),

            // 수강생 선택 카드
            _buildRoleCard(
              context,
              title: '수강생으로 가입하기',
              subtitle: '나에게 맞는 스포츠 멘토를 찾고 싶어요',
              icon: Icons.person_search,
              role: 'student',
            ),
            const SizedBox(height: 20),

            // 코치 선택 카드
            _buildRoleCard(
              context,
              title: '전문 코치로 가입하기',
              subtitle: '나만의 노하우를 수강생들에게 나누고 싶어요',
              icon: Icons.sports,
              role: 'coach',
            ),
            if (widget.completeProfile) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: _signingOut ? null : _switchAccount,
                child: Text(_signingOut ? '계정 변경 중…' : '다른 계정으로 로그인'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required String role}) {
    return InkWell(
      onTap: _signingOut
          ? null
          : () {
              // 역할을 선택하면 SignupScreen으로 역할(role) 데이터와 함께 이동
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SignupScreen(
                      role: role, completeProfile: widget.completeProfile),
                ),
              );
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C29),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: const Color(0xFF38BDF8)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}
