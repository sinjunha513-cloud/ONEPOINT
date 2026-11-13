import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:onepoint_lesson/screens/instructor_registration_screen.dart';
import 'package:onepoint_lesson/config/sports.dart';

void main() {
  testWidgets(
      'sport selection remains visible after each change on dark background',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'coach'), signedIn: true);
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InstructorRegistrationScreen(auth: auth, firestore: db)));
    await tester.pumpAndSettle();
    for (final sport in ['농구', '테니스', '배드민턴', '클라이밍']) {
      final dropdown = find.byKey(const ValueKey('coach-sport'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(sport).last);
      await tester.pumpAndSettle();
      expect(find.text(sport).hitTestable(), findsOneWidget);
      expect(tester.widget<Text>(find.text(sport).hitTestable()).style!.color,
          Colors.white);
    }
    for (final level in coachWelcomeLevels) {
      final dropdown = find.byKey(const ValueKey('coach-lesson-level'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(level).last);
      await tester.pumpAndSettle();
      expect(find.text(level).hitTestable(), findsOneWidget);
    }
    expect(find.text('경력 PDF 업로드 (5MB 이하)'), findsOneWidget);
  });
}
