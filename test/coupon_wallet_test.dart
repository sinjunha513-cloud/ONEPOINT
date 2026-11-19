import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/screens/coupon_wallet_screen.dart';
import 'package:onepoint_lesson/services/coupon_service.dart';
import 'package:onepoint_lesson/widgets/monthly_lesson_goal_card.dart';
import 'support/fake_functions.dart';

void main() {
  testWidgets(
      'monthly goal claims once and the wallet exposes the received coupon',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    var calls = 0;
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    final month = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final service = CouponService(
        firestore: db,
        auth: auth,
        functions: FakeFunctions((name, data) async {
          expect(name, 'claimMonthlyCoupon');
          expect(data, isEmpty);
          calls++;
          await db.doc('users/me/coupons/monthly_$month').set({
            'status': 'available',
            'earnedMonth': month,
            'expiresAt':
                Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))
          });
          return {'couponId': 'monthly_$month'};
        }));
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MonthlyLessonGoalCard(
                    uid: 'me',
                    role: 'student',
                    loaded: true,
                    hasError: false,
                    service: service,
                    lessons: List.generate(
                        10,
                        (_) => {
                              'studentUid': 'me',
                              'status': 'completed',
                              'completedAt': Timestamp.now()
                            }))))));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.text('10% 할인권 받기'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('이번 달 할인권 받기 완료'), findsOneWidget);
    await tester.tap(find.text('내 할인권'));
    await tester.pumpAndSettle();
    expect(find.text('10% OFF'), findsOneWidget);
    expect(find.text('사용 가능'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'wallet only applies available unexpired coupons to the selected lesson',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    for (final e in {
      'available': 'available',
      'expired': 'available',
      'used': 'used',
      'reserved': 'reserved'
    }.entries) {
      await db.doc('users/me/coupons/${e.key}').set({
        'status': e.value,
        'earnedMonth': '202611',
        'expiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: e.key == 'expired' ? -1 : 10)))
      });
    }
    final calls = <Map<String, dynamic>>[];
    final service = CouponService(
        firestore: db,
        auth: auth,
        functions: FakeFunctions((name, data) async {
          expect(name, 'applyLessonCoupon');
          calls.add(data);
          return {};
        }));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CouponWalletScreen(
                                service: service, lessonId: 'lesson'))),
                    child: const Text('열기'))))));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('사용 완료'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('기간 만료'), 300,
        scrollable: find.byType(Scrollable));
    expect(find.text('기간 만료'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('이 레슨에 적용'), 300,
        scrollable: find.byType(Scrollable));
    expect(find.text('이 레슨에 적용'), findsOneWidget);
    await tester.ensureVisible(find.text('이 레슨에 적용'));
    await tester.tap(find.text('이 레슨에 적용'));
    await tester.pumpAndSettle();
    expect(calls, [
      {'lessonId': 'lesson', 'couponId': 'available'}
    ]);
    expect(find.text('열기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
