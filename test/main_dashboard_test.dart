import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/screens/main_screen.dart';

void main() {
  testWidgets('recommendation reacts to the signed-in student profile',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'student'));
    await db.doc('users/student').set({
      'preferredSport': '축구',
      'experienceLevel': '초급',
      'learningGoal': '패스'
    });
    for (final e in {'football': '축구', 'tennis': '테니스'}.entries) {
      await db.doc('public_instructors/${e.key}').set({
        'uid': e.key,
        'name': '${e.value} 맞춤 코치',
        'sport': e.value,
        'lessonLevel': '초급 환영',
        'signatureMove': e.value == '축구' ? '패스' : '서브',
        'status': 'approved'
      });
    }
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: MainScreen(firestore: db, auth: auth)));
    await tester.pumpAndSettle();
    expect(find.text('축구 맞춤 코치'), findsOneWidget);
    expect(find.textContaining('관심 종목 축구'), findsOneWidget);
    await db
        .doc('users/student')
        .update({'preferredSport': '테니스', 'learningGoal': '서브'});
    await tester.pumpAndSettle();
    expect(find.text('테니스 맞춤 코치'), findsOneWidget);
    expect(find.textContaining('관심 종목 테니스'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dashboard uses live lessons and counts only verified own badges',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'student'));
    for (final entry in {
      'pending': 'pending',
      'accepted': 'accepted',
      'verified': 'completed',
      'legacy': 'completed',
    }.entries) {
      await db.collection('lesson_requests').doc(entry.key).set({
        'participantIds': ['student', 'coach'],
        'studentUid': 'student',
        'status': entry.value,
        if (entry.value == 'completed') 'completedAt': Timestamp.now(),
        if (entry.key == 'verified')
          'attendanceBadge': {
            'instructorUid': 'coach',
            'instructorName': '테스트 코치',
            'signatureMove': '패스',
          },
      });
    }
    await db.collection('public_instructors').doc('football').set({
      'name': '축구 코치',
      'sport': '축구',
      'status': 'approved',
    });
    await db.collection('public_instructors').doc('yoga').set({
      'name': '요가 코치',
      'sport': '요가',
      'status': 'approved',
    });
    await db.collection('public_instructors').doc('hidden').set({
      'name': '미승인 코치',
      'sport': '축구',
      'status': 'pending',
    });

    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildOnepointTheme(),
      home: MainScreen(firestore: db, auth: auth),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('100%까지 80%, 8회 남았어요.'), findsOneWidget);
    expect(find.text('1개 획득'), findsOneWidget);
    expect(find.text('미승인 코치'), findsNothing);
    expect(find.textContaining('요가 코치'), findsWidgets);
    expect(find.byTooltip('알림'), findsOneWidget);

    await db
        .collection('lesson_requests')
        .doc('accepted')
        .update({'status': 'completed', 'completedAt': Timestamp.now()});
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);
    // A completed legacy lesson does not mint an attendance badge.
    expect(find.text('1개 획득'), findsOneWidget);

    await tester.ensureVisible(find.text('전체 종목'));
    await tester.tap(find.text('전체 종목'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('요가').last);
    await tester.pumpAndSettle();
    expect(find.text('요가 코치'), findsWidgets);
    expect(find.text('축구 코치'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
