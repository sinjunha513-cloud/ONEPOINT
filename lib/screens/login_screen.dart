// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'role_selection_screen.dart';
import 'session_gate_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.service, this.homeBuilder});

  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  late final AuthService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AuthService();
  }

  void _openSession() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => SessionGateScreen(
            service: _service, homeBuilder: widget.homeBuilder),
      ),
      (route) => false,
    );
  }

  void _showLoginError(Object error) {
    if (!mounted) return;
    final message = error is FirebaseAuthException
        ? switch (error.code) {
            'invalid-email' => '이메일 주소를 확인해 주세요.',
            'user-not-found' ||
            'wrong-password' ||
            'invalid-credential' =>
              '이메일 또는 비밀번호를 확인해 주세요.',
            'user-disabled' => '사용이 제한된 계정입니다.',
            'popup-blocked' => '브라우저에서 팝업을 허용한 뒤 다시 시도해 주세요.',
            'account-exists-with-different-credential' =>
              '이미 이메일로 가입한 계정입니다. 기존 비밀번호로 Google 로그인을 연결해 주세요.',
            'provider-already-linked' =>
              '이미 Google 로그인이 연결된 계정입니다. 다시 시도해 주세요.',
            'credential-already-in-use' =>
              '이 Google 계정은 다른 ONEPOINT 계정에 연결되어 있습니다.',
            'network-request-failed' => '인터넷 연결을 확인해 주세요.',
            'too-many-requests' => '잠시 후 다시 로그인해 주세요.',
            'operation-not-allowed' ||
            'unauthorized-domain' =>
              '현재 구글 로그인을 사용할 수 없습니다. 이메일 로그인을 이용해 주세요.',
            'web-storage-unsupported' =>
              '브라우저의 쿠키 또는 저장소 사용을 허용한 뒤 다시 시도해 주세요.',
            _ => '로그인에 실패했습니다. 다시 시도해 주세요.',
          }
        : '로그인 정보를 불러오지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleGoogleLogin() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _isGoogleLoading = true;
    });
    try {
      final user = await _service.signInWithGoogle();
      if (mounted && user != null) _openSession();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'account-exists-with-different-credential' &&
          error.email != null &&
          error.credential != null) {
        await _linkExistingGoogleAccount(error);
      } else {
        _showLoginError(error);
      }
    } catch (error) {
      _showLoginError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _linkExistingGoogleAccount(
      FirebaseAuthException conflict) async {
    final password = await _requestExistingPassword(conflict.email!);
    if (!mounted) return;
    if (password == null) {
      _showLoginError(conflict);
      return;
    }
    try {
      final user = await _service.linkGoogleToPasswordAccount(
        conflict: conflict,
        password: password,
      );
      if (mounted && user != null) _openSession();
    } catch (error) {
      _showLoginError(error);
    }
  }

  Future<String?> _requestExistingPassword(String email) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GoogleLinkPasswordDialog(email: email),
    );
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 모두 입력해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = await _service.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted && user != null) _openSession();
    } catch (error) {
      _showLoginError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 확인된 assets/icon/ 경로 반영
                Center(
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 90,
                    height: 90,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '원포인트',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '나만의 스포츠 멘토를 만나보세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 48),

                // 이메일 입력
                TextField(
                  key: const ValueKey('login-email'),
                  enabled: !_isLoading,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '이메일',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1A1C29),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon:
                        const Icon(Icons.email_outlined, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 16),

                // 비밀번호 입력
                TextField(
                  key: const ValueKey('login-password'),
                  enabled: !_isLoading,
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '비밀번호',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1A1C29),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 32),

                // 로그인 버튼
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading && !_isGoogleLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text(
                            '로그인',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white12)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child:
                          Text('또는', style: TextStyle(color: Colors.white38)),
                    ),
                    Expanded(child: Divider(color: Colors.white12)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const ValueKey('google-login'),
                    onPressed: _isLoading ? null : _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF202124),
                      disabledBackgroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isGoogleLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login_rounded, size: 20),
                    label:
                        Text(_isGoogleLoading ? '구글 로그인 중…' : 'Google로 계속하기'),
                  ),
                ),
                const SizedBox(height: 24),

                // 추가된 기능: 회원가입 버튼 클릭 시 역할 선택 화면으로 이동
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '아직 계정이 없으신가요?',
                      style: TextStyle(color: Colors.white54),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const RoleSelectionScreen(),
                                ),
                              );
                            },
                      child: const Text(
                        '회원가입',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleLinkPasswordDialog extends StatefulWidget {
  const _GoogleLinkPasswordDialog({required this.email});

  final String email;

  @override
  State<_GoogleLinkPasswordDialog> createState() =>
      _GoogleLinkPasswordDialogState();
}

class _GoogleLinkPasswordDialogState extends State<_GoogleLinkPasswordDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('기존 계정에 Google 연결'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${widget.email} 계정의 기존 비밀번호를 입력하면 앞으로 Google로도 로그인할 수 있습니다.'),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('google-link-password'),
                  controller: _controller,
                  autofocus: true,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '기존 비밀번호',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? '비밀번호를 입력해 주세요.' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('연결하고 로그인'),
          ),
        ],
      );
}
