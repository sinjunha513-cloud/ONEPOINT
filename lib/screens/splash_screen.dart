import 'package:flutter/material.dart';
import 'dart:async';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../widgets/onepoint_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.service, this.homeBuilder});

  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showLogo = false;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showLogo = true);

    await Future.delayed(const Duration(milliseconds: 1900));
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
        child: AnimatedSlide(
          offset: _showLogo ? Offset.zero : const Offset(0, 0.15),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _showLogo ? 1 : 0,
            duration: const Duration(milliseconds: 800),
            child: const OnepointLogo(),
          ),
        ),
      ),
    );
  }
}
