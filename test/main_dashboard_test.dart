import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/screens/main_screen.dart';

void main() {
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
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('1개 획득'), findsOneWidget);
    expect(find.text('미승인 코치'), findsNothing);
    expect(find.textContaining('요가 코치'), findsWidgets);
    expect(find.byTooltip('알림'), findsOneWidget);

    await db
        .collection('lesson_requests')
        .doc('accepted')
        .update({'status': 'completed'});
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    // A completed legacy lesson does not mint an attendance badge.
    expect(find.text('1개 획득'), findsOneWidget);

    await tester.ensureVisible(find.text('전체 종목'));
    await tester.tap(find.text('전체 종목'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('요가'));
    await tester.pumpAndSettle();
    expect(find.text('요가 코치'), findsWidgets);
    expect(find.text('축구 코치'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
