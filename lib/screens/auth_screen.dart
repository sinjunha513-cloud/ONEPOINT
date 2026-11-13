import 'package:flutter/material.dart';
import 'main_screen.dart'; // 메인 화면 파일 임포트

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignUpMode = false; // false: 로그인 모드, true: 회원가입 모드

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              Text(
                isSignUpMode ? '회원가입' : '원포인트레슨',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // 회원가입 모드일 때만 이름 입력창 표시
              if (isSignUpMode) ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // 로그인 / 회원가입 버튼
              ElevatedButton(
                onPressed: () {
                  if (isSignUpMode) {
                    // 1. 회원가입 버튼 눌렀을 때
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('회원가입 완료! 로그인해 주세요.')),
                    );
                    setState(() {
                      isSignUpMode = false; // 로그인 모드로 전환
                    });
                  } else {
                    // 2. 로그인 버튼 눌렀을 때 (MainScreen으로 이동)
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainScreen(),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  isSignUpMode ? '가입하기' : '로그인',
                  style: const TextStyle(fontSize: 16),
                ),
              ),

              // 모드 전환 버튼 (로그인 <-> 회원가입)
              TextButton(
                onPressed: () {
                  setState(() {
                    isSignUpMode = !isSignUpMode;
                  });
                },
                child: Text(
                  isSignUpMode ? '이미 계정이 있으신가요? 로그인' : '계정이 없으신가요? 회원가입',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
