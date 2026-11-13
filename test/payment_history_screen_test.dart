import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/payment_history_screen.dart';
import 'package:onepoint_lesson/services/payment_service.dart';

void main() {
  testWidgets('PG 설정 전에는 일반 오류 대신 결제 준비 상태를 안내한다', (tester) async {
    final service = PaymentService(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PaymentHistoryScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('결제 테스트 연동 준비 중'), findsOneWidget);
    expect(find.textContaining('토스페이먼츠 테스트 상점 키'), findsOneWidget);
    expect(find.textContaining('요청을 처리하지 못했습니다'), findsNothing);
  });
}
