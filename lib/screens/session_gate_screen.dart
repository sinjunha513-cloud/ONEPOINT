import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';
import 'role_selection_screen.dart';
import 'instructor_registration_screen.dart';

enum _Destination { login, profile, coachApplication, home, failed, blocked }

/// Restores Firebase's saved session before deciding which screen to show.
class SessionGateScreen extends StatefulWidget {
  const SessionGateScreen({super.key, this.service, this.homeBuilder});

  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<SessionGateScreen> createState() => _SessionGateScreenState();
}

class _SessionGateScreenState extends State<SessionGateScreen> {
  late final AuthService _service;
  Future<_Destination>? _destination;
  StreamSubscription<User?>? _subscription;
  StreamSubscription<String>? _accountSubscription;
  String? _lastUid;
  bool _receivedUser = false;
  bool _authError = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AuthService();
    _watchAuth();
  }

  void _watchAuth() {
    _subscription?.cancel();
    _receivedUser = false;
    _subscription = _service.authStateChanges().listen((user) {
      if (!mounted) return;
      if (_receivedUser && _lastUid == user?.uid) return;
      setState(() {
        _receivedUser = true;
        _lastUid = user?.uid;
        _authError = false;
        _destination = _load(user?.uid);
        _accountSubscription?.cancel();
        if (user != null) {
          _accountSubscription =
              _service.accountStatus(user.uid).listen((status) {
            if (mounted && status != 'active') {
              setState(() => _destination = Future.value(_Destination.blocked));
            }
          }, onError: (Object _) {});
        }
      });
    }, onError: (Object error) {
      if (mounted) setState(() => _authError = true);
    });
  }

  Future<_Destination> _load(String? uid) async {
    if (uid == null) return _Destination.login;
    try {
      final incomplete = await _service.needsProfileCompletion();
      if (!incomplete) return _Destination.home;
      return await _service.incompleteRequestedRole() == 'coach'
          ? _Destination.coachApplication
          : _Destination.profile;
    } on FirebaseAuthException catch (error) {
      return error.code == 'user-disabled'
          ? _Destination.blocked
          : _Destination.failed;
    } catch (_) {
      // The auth stream can emit before FutureBuilder attaches its listener.
      return _Destination.failed;
    }
  }

  void _retry() {
    if (_authError) {
      setState(() {
        _authError = false;
        _destination = null;
      });
      _watchAuth();
    } else {
      setState(() {
        _destination = _load(_service.currentUser?.uid);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _accountSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      await _service.signOut();
      if (mounted) _retry();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃하지 못했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Destination>(
        future: _destination,
        builder: (context, snapshot) {
          if (_authError ||
              (snapshot.connectionState == ConnectionState.done &&
                  snapshot.data == _Destination.failed)) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('프로필을 불러오지 못했습니다.\n연결 상태를 확인해 주세요.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _retry, child: const Text('다시 시도')),
                      TextButton(
                          onPressed: _signOut,
                          child: const Text('다른 계정으로 로그인')),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return switch (snapshot.data) {
            _Destination.blocked => Scaffold(
                  body: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('이용이 정지되었거나 삭제된 계정입니다.'),
                TextButton(onPressed: _signOut, child: const Text('로그아웃')),
              ]))),
            _Destination.login =>
              LoginScreen(service: _service, homeBuilder: widget.homeBuilder),
            _Destination.profile => RoleSelectionScreen(
                completeProfile: true,
                service: _service,
                homeBuilder: widget.homeBuilder),
            _Destination.coachApplication => InstructorRegistrationScreen(
                completeSignup: true,
                auth: _service.auth,
                firestore: _service.firestore,
              ),
            _Destination.home =>
              widget.homeBuilder?.call(context) ?? const MainNavigationScreen(),
            _Destination.failed ||
            null =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          };
        },
      );
}
