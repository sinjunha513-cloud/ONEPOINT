import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/admin_dashboard_screen.dart';

void main() {
  testWidgets('ordinary users cannot open member management', (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'student'), signedIn: true);
    await db.collection('users').doc('student').set({'role': 'student'});
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(auth: auth, firestore: db)));
    await tester.pumpAndSettle();
    expect(find.text('관리자만 접근할 수 있습니다.'), findsOneWidget);
    expect(find.text('회원 관리'), findsNothing);
  });

  testWidgets(
      'admin can assign coach without application and loses UI access after revocation',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'admin'), signedIn: true);
    await db
        .collection('users')
        .doc('admin')
        .set({'role': 'admin', 'name': '운영자', 'profileCompleted': true});
    final member = db.collection('users').doc('member');
    await member
        .set({'role': 'student', 'name': '회원', 'profileCompleted': true});
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(auth: auth, firestore: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('회원 관리'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('member-role-admin')))
            .onChanged,
        isNull);
    await tester.tap(find.byKey(const ValueKey('member-role-member')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('코치').last);
    await tester.pumpAndSettle();
    expect((await member.get()).data()!['role'], 'coach');
    expect(
        (await db.collection('instructors').doc('member').get()).exists, false);
    await db.collection('users').doc('admin').update({'role': 'student'});
    await tester.pumpAndSettle();
    expect(find.text('관리자만 접근할 수 있습니다.'), findsOneWidget);
    expect(find.text('회원 관리'), findsNothing);
  });
}
