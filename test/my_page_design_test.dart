import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/screens/my_page_screen.dart';
import 'package:onepoint_lesson/services/auth_service.dart';

void main() {
  testWidgets('logout requires confirmation and cancel keeps the session',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'member'));
    await db
        .collection('users')
        .doc('member')
        .set({'name': '회원', 'role': 'student'});
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: MyPageScreen(
            firestore: db,
            auth: auth,
            sessionService:
                AuthService(firestore: db, auth: auth, isWeb: true))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('계정 및 활동 관리'));
    await tester.tap(find.text('계정 및 활동 관리'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNotNull);
    expect(find.text('정말 로그아웃하시겠습니까?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-logout')));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNotNull);
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-logout')));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
  });
  testWidgets(
      'profile uses live verified awards and lessons on a narrow screen',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'member'));
    await db.collection('users').doc('member').set({
      'name': '긴 이름을 가진 테스트 회원',
      'role': 'student',
      'lessonCount': 3,
      'targetTier': '프로 1',
    });
    final completed = db.collection('lesson_requests').doc('verified');
    await completed.set({
      'studentUid': 'member',
      'instructorUid': 'coach',
      'participantIds': ['member', 'coach'],
      'status': 'completed',
      'sport': '축구',
      'instructorName': '검증 코치',
      'signatureMove': '패스',
      'attendanceBadge': {
        'instructorUid': 'coach',
        'instructorName': '검증 코치',
        'signatureMove': '패스'
      },
    });
    await db.collection('lesson_requests').doc('active').set({
      'studentUid': 'member',
      'participantIds': ['member', 'coach'],
      'instructorUid': 'coach',
      'status': 'accepted',
      'sport': '배드민턴',
      'signatureMove': '현재 진행 레슨',
    });
    await db.collection('lesson_requests').doc('foreign').set({
      'studentUid': 'other',
      'participantIds': ['other', 'coach'],
      'status': 'accepted',
      'signatureMove': '다른 회원 레슨',
    });
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: MyPageScreen(firestore: db, auth: auth)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('나의 프로필'), findsOneWidget);
    expect(find.text('프로 1'), findsOneWidget);
    expect(find.text('1개 획득'), findsOneWidget);
    expect(find.text('현재 진행 레슨'), findsOneWidget);
    expect(find.text('다른 회원 레슨'), findsNothing);
    expect(find.text('75%'), findsNothing);

    await completed.update({'attendanceBadge': null});
    await tester.pumpAndSettle();
    expect(find.text('0개 획득'), findsOneWidget);
    expect(find.text('아직 미획득'), findsOneWidget);

    await tester.ensureVisible(find.text('계정 및 활동 관리'));
    await tester.tap(find.text('계정 및 활동 관리'));
    await tester.pumpAndSettle();
    expect(find.text('나의 결제 내역'), findsOneWidget);
    expect(find.text('프로필 및 정보 수정하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final role in ['coach', 'admin']) {
    testWidgets('$role retains account actions after the profile redesign',
        (tester) async {
      final db = FakeFirebaseFirestore();
      final auth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: role));
      await db
          .collection('users')
          .doc(role)
          .set({'name': '테스트 계정', 'role': role});
      await tester.binding.setSurfaceSize(const Size(428, 926));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: buildOnepointTheme(),
          home: MyPageScreen(firestore: db, auth: auth)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('계정 및 활동 관리'));
      await tester.tap(find.text('계정 및 활동 관리'));
      await tester.pumpAndSettle();
      expect(find.text(role == 'admin' ? '관리자 대시보드' : '레슨 가능 날짜·시간 관리'),
          findsOneWidget);
      expect(find.text(role == 'admin' ? '결제 관리' : '정산 예정 내역'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
