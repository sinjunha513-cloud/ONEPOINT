import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/account_settings_screen.dart';
import 'package:onepoint_lesson/screens/password_reset_screen.dart';
import 'package:onepoint_lesson/services/auth_service.dart';
import 'package:onepoint_lesson/services/media_playback_service.dart';
import 'package:onepoint_lesson/utils/tier_calculator.dart';
import 'package:onepoint_lesson/widget/video_item_widget.dart';
import 'support/fake_functions.dart';

class _ResetAuth extends MockFirebaseAuth {
  String? language, address;
  Object? failure;
  int calls = 0;
  Completer<void>? pending;
  @override
  Future<void> setLanguageCode(String? code) async {
    language = code;
  }

  @override
  Future<void> sendPasswordResetEmail(
      {required String email, ActionCodeSettings? actionCodeSettings}) async {
    address = email;
    calls++;
    if (failure != null) throw failure!;
    if (pending != null) await pending!.future;
  }
}

class _WithdrawalAuth extends AuthService {
  _WithdrawalAuth()
      : super(
            auth: MockFirebaseAuth(
                mockUser: MockUser(uid: 'member'), signedIn: true),
            firestore: FakeFirebaseFirestore());
  int reauthCalls = 0;
  @override
  Future<void> reauthenticateForAccountChange(String password) async {
    reauthCalls++;
    throw StateError('cancelled');
  }
}

void main() {
  test(
      'password recovery validates email, trims it and conceals missing accounts',
      () async {
    final auth = _ResetAuth(),
        service = AuthService(auth: auth, firestore: FakeFirebaseFirestore());
    await expectLater(
        service.resetPassword('bad-address'), throwsArgumentError);
    expect(auth.calls, 0);
    auth.failure = FirebaseAuthException(code: 'user-not-found');
    await service.resetPassword('  member@example.com  ');
    expect(auth.language, 'ko');
    expect(auth.address, 'member@example.com');
    auth.failure = FirebaseAuthException(code: 'network-request-failed');
    await expectLater(service.resetPassword('member@example.com'),
        throwsA(isA<FirebaseAuthException>()));
  });
  testWidgets(
      'password recovery submits on Enter once and provides a generic success message',
      (tester) async {
    final auth = _ResetAuth()..pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: PasswordResetScreen(
            service:
                AuthService(auth: auth, firestore: FakeFirebaseFirestore()))));
    await tester.enterText(find.byType(TextField), 'member@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.calls, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('가입한 이메일이라면'), findsOneWidget);
    expect(find.text('로그인으로 돌아가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'withdrawal requires explicit confirmation and cancellation never calls the server',
      (tester) async {
    final auth = _WithdrawalAuth();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: AccountSettingsScreen(
            service: auth,
            functions: FakeFunctions((name, data) async {
              calls++;
              return {};
            }))));
    await tester.tap(find.text('회원탈퇴'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '인증하고 탈퇴 요청');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '회원탈퇴');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(auth.reauthCalls, 0);
    expect(calls, 0);
    await tester.tap(find.text('회원탈퇴'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '회원탈퇴');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(auth.reauthCalls, 1);
    expect(calls, 0);
    expect(find.textContaining('다시 인증하거나'), findsOneWidget);
  });
  test('activity tier only counts completed lessons and caps the highest tier',
      () {
    TierProgressInfo tier(int n,
            {int likes = 0, List<double> scores = const []}) =>
        TierCalculator.calculateTierInfo(
            lessonCount: n,
            reviewScores: scores,
            teacherMatchCount: 900,
            feedLikeCount: likes);
    expect(tier(0, likes: 9999, scores: [5, 5]).totalExp, 0);
    expect(tier(5).totalExp, 100);
    expect(tier(5).currentTierExp, 0);
    expect(tier(-2).totalExp, 0);
    expect(tier(1).isGeneralMember, isTrue);
    expect(tier(1000).progressRatio, 1);
    expect(tier(1000).tierName, TierCalculator.tierList.last);
  });
  test(
      'media requests include lesson context and reject non-HTTPS playback URLs',
      () async {
    final payloads = <Map<String, dynamic>>[];
    final service =
        MediaPlaybackService(functions: FakeFunctions((name, data) async {
      expect(name, 'getMediaPlayback');
      payloads.add(data);
      return {
        'url': payloads.length == 1
            ? 'https://storage.googleapis.com/private/video.mp4'
            : 'http://unsafe.test/clip.mp4'
      };
    }));
    expect((await service.url(videoId: 'clip', lessonId: 'lesson')).scheme,
        'https');
    expect(payloads.single,
        {'kind': 'feedback', 'videoId': 'clip', 'lessonId': 'lesson'});
    await expectLater(service.url(videoId: 'public'), throwsStateError);
  });
  testWidgets(
      'inactive and manually played videos do not fetch or initialize media',
      (tester) async {
    var calls = 0;
    final service =
        MediaPlaybackService(functions: FakeFunctions((name, data) async {
      calls++;
      throw StateError('offline');
    }));
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      SizedBox(
          height: 180,
          child: VideoItemWidget(
              videoUrl: '',
              videoId: 'inactive',
              isPlaying: false,
              service: service)),
      SizedBox(
          height: 180,
          child: VideoItemWidget(
              videoUrl: '',
              videoId: 'manual',
              autoplay: false,
              service: service)),
    ])));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byTooltip('영상 재생').last);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byTooltip('영상 다시 불러오기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
