import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/screens/main_screen.dart';
import 'package:onepoint_lesson/screens/notifications_screen.dart';
import 'package:onepoint_lesson/services/notification_inbox_service.dart';
import 'support/fake_functions.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late NotificationInboxService service;
  Future<void> notice(String uid, String id,
          {String target = 'lesson', int seconds = 100}) =>
      db.collection('users').doc(uid).collection('notifications').doc(id).set({
        'title': '알림 $id',
        'body': '실제 활동 미리보기 $id',
        'kind': 'lesson',
        'targetType': target,
        'targetId': 'lesson',
        'createdAt': Timestamp(seconds, 0),
        'readAt': null
      });
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'member'));
    service = NotificationInboxService(
        firestore: db,
        auth: auth,
        functions: FakeFunctions((_, __) async => {'cursor': null}));
  });
  test('inbox is newest first and bulk read only changes the current owner',
      () async {
    for (var i = 0; i < 405; i++) {
      await notice('member', 'n$i', seconds: i);
    }
    await notice('other', 'private');
    final list = await service.watch(limit: 500).first;
    expect(list.length, 405);
    expect(list.first.id, 'n404');
    expect(list.any((n) => n.id == 'private'), isFalse);
    await service.markAllRead();
    expect(
        (await service.watch(limit: 500).first).any((n) => n.unread), isFalse);
    expect(
        (await db.doc('users/other/notifications/private').get())
            .data()!['readAt'],
        isNull);
  });
  test(
      'historical activity sync follows every server page and forbids choosing another UID',
      () async {
    final calls = <Map<String, dynamic>>[];
    service = NotificationInboxService(
        firestore: db,
        auth: auth,
        functions: FakeFunctions((name, data) async {
          expect(name, 'syncMyNotifications');
          calls.add(data);
          return {
            'cursor': data['category'] == 'lessons' && data['cursor'] == null
                ? 'page2'
                : null
          };
        }));
    await service.syncExisting();
    expect(calls.map((d) => d['category']),
        ['lessons', 'lessons', 'chats', 'profile']);
    expect(calls[1]['cursor'], 'page2');
    expect(calls.every((d) => !d.containsKey('uid')), isTrue);
  });
  testWidgets(
      'previews open the related lesson and preserve read state on rebuild',
      (tester) async {
    await notice('member', 'own');
    await notice('other', 'private');
    await db.collection('lesson_requests').doc('lesson').set({
      'participantIds': ['member', 'coach'],
      'studentUid': 'member',
      'instructorUid': 'coach',
      'instructorName': '테스트 코치',
      'studentName': '회원',
      'status': 'pending'
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: NotificationsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('실제 활동 미리보기 own'), findsOneWidget);
    expect(find.text('실제 활동 미리보기 private'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notification-own')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lesson-card-lesson')), findsOneWidget);
    expect(
        (await db.doc('users/member/notifications/own').get())
            .data()!['readAt'],
        isA<Timestamp>());
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect((await service.watch().first).single.unread, isFalse);
  });
  testWidgets('empty inbox has no shortcut menu or fabricated activity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: NotificationsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('아직 알림이 없어요'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('코치 등록 · 승인 관리'), findsNothing);
  });
  testWidgets(
      'home has separate badge, lesson and notification actions on 320px',
      (tester) async {
    await db
        .collection('users')
        .doc('member')
        .set({'name': '회원', 'role': 'student'});
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: MainScreen(firestore: db, auth: auth)));
    await tester.pumpAndSettle();
    for (final label in ['내 뱃지', '내 레슨', '알림']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('나의 뱃지'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('내 레슨'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lessons-보낸 신청')), findsOneWidget);
    expect(find.byKey(const ValueKey('lessons-받은 신청')), findsOneWidget);
  });
}
