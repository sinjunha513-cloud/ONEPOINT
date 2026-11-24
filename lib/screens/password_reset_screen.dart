import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/onepoint_logo.dart';
import '../config/onepoint_design.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen(
      {super.key, required this.service, this.initialEmail = ''});
  final AuthService service;
  final String initialEmail;
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false, _sent = false;
  String? _error;
  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.resetPassword(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ArgumentError
            ? e.message.toString()
            : '메일을 보내지 못했습니다. 연결 상태를 확인하고 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('비밀번호 재설정')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: OnepointLogo(width: 180)),
                    const SizedBox(height: 32),
                    Text(_sent ? '재설정 안내를 확인해 주세요' : '가입한 이메일을 입력해 주세요',
                        style: OnepointDesign.heading),
                    const SizedBox(height: 12),
                    Text(
                        _sent
                            ? '가입한 이메일이라면 비밀번호 재설정 메일이 발송됩니다. 스팸함도 확인해 주세요. Google로 가입했다면 Google 로그인을 이용해 주세요.'
                            : '비밀번호를 다시 설정할 수 있는 링크를 보내드립니다.',
                        style: const TextStyle(
                            color: OnepointDesign.muted, height: 1.6)),
                    const SizedBox(height: 24),
                    if (!_sent) ...[
                      TextField(
                          controller: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                              labelText: '이메일',
                              errorText: _error,
                              filled: true,
                              fillColor: OnepointDesign.surface,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none))),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _busy ? null : _send,
                          child: Text(_busy ? '메일 보내는 중…' : '재설정 메일 보내기')),
                    ] else
                      FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('로그인으로 돌아가기')),
                  ])),
        )),
      );
}
