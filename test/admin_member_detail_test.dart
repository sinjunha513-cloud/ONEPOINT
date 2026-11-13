import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/admin_member_detail_screen.dart';

void main() {
  testWidgets('admin details are live, read only and omit sensitive fields',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'admin'), signedIn: true);
    await db.collection('users').doc('admin').set({'role': 'admin'});
    final member = db.collection('users').doc('member');
    await member.set({
      'name': '테스트 회원',
      'email': 'member@example.com',
      'role': 'student',
      'requestedRole': 'coach',
      'profileCompleted': true,
      'fcmToken': 'secret-token',
      'password': 'secret-password'
    });
    await db
        .collection('instructors')
        .doc('member')
        .set({'status': 'pending', 'sport': '축구'});
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home:
            AdminMemberDetailScreen(uid: 'member', auth: auth, firestore: db)));
    await tester.pumpAndSettle();
    expect(find.textContaining('테스트 회원'), findsOneWidget);
    expect(find.textContaining('가입 완료'), findsOneWidget);
    expect(find.textContaining('승인 대기'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('secret-password'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    await member.update({'name': '새 이름'});
    await tester.pumpAndSettle();
    expect(find.textContaining('새 이름'), findsOneWidget);
    await member.delete();
    await tester.pumpAndSettle();
    expect(find.text('회원 정보를 찾을 수 없습니다.'), findsOneWidget);
  });
  testWidgets('ordinary users cannot enter the admin detail screen',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'student'), signedIn: true);
    await db.collection('users').doc('student').set({'role': 'student'});
    await db.collection('users').doc('member').set({'name': '비공개 상세'});
    await tester.pumpWidget(MaterialApp(
        home:
            AdminMemberDetailScreen(uid: 'member', auth: auth, firestore: db)));
    await tester.pumpAndSettle();
    expect(find.text('관리자만 조회할 수 있습니다.'), findsOneWidget);
    expect(find.textContaining('비공개 상세'), findsNothing);
  });
}
