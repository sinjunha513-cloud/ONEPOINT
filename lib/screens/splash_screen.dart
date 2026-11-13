import 'package:flutter/material.dart';
import 'dart:async';
import 'login_screen.dart';
import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.service, this.homeBuilder});

  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showOne = false;
  bool _showPoint = false;
  bool _showDot = false;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showOne = true);

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showPoint = true);

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showDot = true);

    await Future.delayed(const Duration(milliseconds: 1300));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => LoginScreen(
                service: widget.service, homeBuilder: widget.homeBuilder)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12), // Black 배경
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSlide(
              offset: _showOne ? Offset.zero : const Offset(-0.5, 0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showOne ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: const Text('one',
                    style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1.0)),
              ),
            ),
            AnimatedScale(
              scale: _showDot ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              child: Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                    color: Color(0xFF38BDF8), shape: BoxShape.circle),
              ),
            ),
            AnimatedSlide(
              offset: _showPoint ? Offset.zero : const Offset(0.5, 0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showPoint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: const Text('oint',
                    style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1.0)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
