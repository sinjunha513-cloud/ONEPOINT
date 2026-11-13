import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/login_screen.dart';
import 'package:onepoint_lesson/screens/role_selection_screen.dart';
import 'package:onepoint_lesson/screens/session_gate_screen.dart';
import 'package:onepoint_lesson/screens/splash_screen.dart';
import 'package:onepoint_lesson/screens/instructor_registration_screen.dart';
import 'package:onepoint_lesson/services/auth_service.dart';

class _TestAuth extends AuthService {
  _TestAuth()
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  User? user;
  bool incomplete = false;
  String? unfinishedRole;
  bool failProfileRead = false;
  Object? googleError;
  Completer<User?>? googlePending;
  StreamController<User?>? sessionUpdates;
  int googleCalls = 0;
  String? email;
  String? password;
  String? googleLinkPassword;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    if (sessionUpdates != null) yield* sessionUpdates!.stream;
  }

  @override
  Future<bool> needsProfileCompletion() async {
    if (failProfileRead) throw StateError('offline');
    return incomplete;
  }

  @override
  Future<String?> incompleteRequestedRole() async => unfinishedRole;

  @override
  Future<User?> signInWithGoogle() async {
    googleCalls++;
    if (googleError != null) throw googleError!;
    if (googlePending != null) return googlePending!.future;
    return user = MockUser(uid: 'google-user', email: 'coach@example.com');
  }

  @override
  Future<User?> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    this.email = email;
    this.password = password;
    return user = MockUser(uid: 'email-user', email: email);
  }

  @override
  Future<User?> linkGoogleToPasswordAccount({
    required FirebaseAuthException conflict,
    required String password,
  }) async {
    googleLinkPassword = password;
    return user = MockUser(
      uid: 'linked-user',
      email: conflict.email,
    );
  }

  @override
  Future<void> signOut() async => user = null;
}

Widget _home(BuildContext context) => const Scaffold(body: Text('인증된 홈'));

void main() {
  testWidgets('startup shows login before an incomplete cached session',
      (tester) async {
    final service = _TestAuth()
      ..user = MockUser(uid: 'unfinished')
      ..incomplete = true;
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(home: SplashScreen(service: service, homeBuilder: _home)));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RoleSelectionScreen), findsNothing);
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
  });
  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('Google login opens home for an existing profile',
      (tester) async {
    final service = _TestAuth();
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pumpAndSettle();
    expect(find.text('인증된 홈'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(service.googleCalls, 1);
  });

  testWidgets('first Google login asks for profile and role completion',
      (tester) async {
    final service = _TestAuth()..incomplete = true;
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pumpAndSettle();
    expect(find.text('가입 유형 선택'), findsOneWidget);
    expect(
        tester
            .widget<RoleSelectionScreen>(find.byType(RoleSelectionScreen))
            .completeProfile,
        isTrue);
    expect(find.text('인증된 홈'), findsNothing);
  });

  testWidgets('Google cancellation restores buttons and cannot double submit',
      (tester) async {
    final service = _TestAuth()..googlePending = Completer<User?>();
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pump();
    expect(find.text('구글 로그인 중…'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('google-login')))
            .onPressed,
        isNull);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    service.googlePending!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(service.googleCalls, 1);
  });

  testWidgets('blocked popup shows an actionable error and permits retry',
      (tester) async {
    final service = _TestAuth()
      ..googleError = FirebaseAuthException(code: 'popup-blocked');
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pumpAndSettle();
    expect(find.text('브라우저에서 팝업을 허용한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('google-login')))
            .onPressed,
        isNotNull);
    expect(find.text('인증된 홈'), findsNothing);
  });

  testWidgets('existing email account can securely link Google login',
      (tester) async {
    final service = _TestAuth()
      ..googleError = FirebaseAuthException(
        code: 'account-exists-with-different-credential',
        email: 'member@example.com',
        credential: GoogleAuthProvider.credential(idToken: 'pending-id-token'),
      );
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기존 계정에 Google 연결'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('google-link-password')),
      'existing-password',
    );
    await tester.tap(find.text('연결하고 로그인'));
    await tester.pumpAndSettle();
    expect(service.googleLinkPassword, 'existing-password');
    expect(find.text('인증된 홈'), findsOneWidget);
  });

  testWidgets('email login preserves meaningful password whitespace',
      (tester) async {
    final service = _TestAuth();
    await show(tester, LoginScreen(service: service, homeBuilder: _home));
    await tester.enterText(
        find.byKey(const ValueKey('login-email')), ' user@example.com ');
    await tester.enterText(
        find.byKey(const ValueKey('login-password')), ' password with spaces ');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(service.email, 'user@example.com');
    expect(service.password, ' password with spaces ');
    expect(find.text('인증된 홈'), findsOneWidget);
  });

  testWidgets('app restart restores a completed session', (tester) async {
    final service = _TestAuth()..user = MockUser(uid: 'returning-user');
    await show(tester, SessionGateScreen(service: service, homeBuilder: _home));
    expect(find.text('인증된 홈'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('interrupted coach signup resumes the approval application',
      (tester) async {
    final service = _TestAuth()
      ..user = MockUser(uid: 'unfinished-coach')
      ..incomplete = true
      ..unfinishedRole = 'coach';
    await service.firestore.collection('users').doc('unfinished-coach').set({
      'role': 'student',
      'requestedRole': 'coach',
      'profileCompleted': false,
    });

    await show(tester, SessionGateScreen(service: service, homeBuilder: _home));

    expect(find.byType(InstructorRegistrationScreen), findsOneWidget);
    expect(find.text('코치 프로필 승인 신청'), findsOneWidget);
    expect(find.byType(RoleSelectionScreen), findsNothing);
    expect(find.text('인증된 홈'), findsNothing);
  });

  testWidgets('signed out app opens login', (tester) async {
    await show(
        tester, SessionGateScreen(service: _TestAuth(), homeBuilder: _home));
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('인증된 홈'), findsNothing);
  });

  testWidgets('profile read error can recover without signing in again',
      (tester) async {
    final service = _TestAuth()
      ..user = MockUser(uid: 'returning-user')
      ..failProfileRead = true;
    await show(tester, SessionGateScreen(service: service, homeBuilder: _home));
    expect(find.textContaining('프로필을 불러오지 못했습니다.'), findsOneWidget);
    service.failProfileRead = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('인증된 홈'), findsOneWidget);
    expect(service.googleCalls, 0);
  });

  testWidgets('incomplete Google profile can switch to another account',
      (tester) async {
    final service = _TestAuth()
      ..user = MockUser(uid: 'wrong-google-account')
      ..incomplete = true;
    await show(tester, SessionGateScreen(service: service, homeBuilder: _home));
    await tester.tap(find.text('다른 계정으로 로그인'));
    await tester.pumpAndSettle();
    expect(service.currentUser, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RoleSelectionScreen), findsNothing);
  });

  testWidgets('changing the authenticated account refreshes the destination',
      (tester) async {
    final updates = StreamController<User?>.broadcast();
    final service = _TestAuth()
      ..sessionUpdates = updates
      ..user = MockUser(uid: 'first-account');
    addTearDown(updates.close);
    await show(tester, SessionGateScreen(service: service, homeBuilder: _home));
    expect(find.text('인증된 홈'), findsOneWidget);
    service.user = MockUser(uid: 'new-incomplete-account');
    service.incomplete = true;
    updates.add(service.user);
    await tester.pumpAndSettle();
    expect(find.byType(RoleSelectionScreen), findsOneWidget);
    expect(find.text('인증된 홈'), findsNothing);
    service.user = null;
    updates.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
