import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/chat_room_screen.dart';
import 'package:onepoint_lesson/services/chat_service.dart';

void main() {
  testWidgets('채팅방 상단의 밝은 뒤로 버튼이 이전 화면으로 돌아간다', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'student'),
    );
    final service = ChatService(firestore: firestore, auth: auth);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      roomId: 'coach_student',
                      targetName: '테스트 코치',
                      service: service,
                    ),
                  ),
                ),
                child: const Text('채팅 열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-back-button')), findsOneWidget);
    expect(find.text('뒤로'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('채팅 열기'), findsOneWidget);
  });
}
