import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/models/lesson_badge.dart';
import 'package:onepoint_lesson/screens/lesson_badges_screen.dart';
import 'package:onepoint_lesson/services/lesson_badge_service.dart';

class _BadgeService implements LessonBadgeService {
  final Stream<List<LessonBadge>> Function() stream;
  int calls = 0;

  _BadgeService(this.stream);

  @override
  Stream<List<LessonBadge>> earnedBadges() {
    calls++;
    return stream();
  }
}

LessonBadge _badge(String id,
        {String coach = 'coach',
        String name = '민수',
        String signature = '스텝백 점프슛',
        String sport = '농구'}) =>
    LessonBadge(
      id: id,
      instructorUid: coach,
      instructorName: name,
      signatureMove: signature,
      sport: sport,
      awardedAt: DateTime(2026, 9, 29),
    );

Future<void> _showCollection(WidgetTester tester, LessonBadgeService service,
    {Size size = const Size(700, 1200), double textScale = 1}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LessonBadgesScreen(service: service),
  ));
  await tester.pump();
}

void main() {
  testWidgets(
      'empty collection explains lesson confirmation and links to lessons',
      (tester) async {
    final service = _BadgeService(() => Stream.value([]));
    await _showCollection(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('수집된 뱃지가 없습니다.'), findsOneWidget);
    expect(find.text('레슨 참여 후 시그니처 뱃지를 수집하세요!'), findsOneWidget);
    expect(find.textContaining('연결 상태를 확인'), findsNothing);
    expect(find.text('내 레슨 보러 가기'), findsOneWidget);
    expect(find.textContaining('앱 접속이 아닌'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('certified-lesson-count')))
            .data,
        '0');
    expect(service.calls, 1);
  });

  testWidgets('each lesson has a badge while signatures are unique per coach',
      (tester) async {
    final service = _BadgeService(() => Stream.value([
          _badge('lesson-1'),
          _badge('lesson-2'),
          _badge('lesson-3', coach: 'another-coach', name: '지수'),
        ]));
    await _showCollection(tester, service);
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<Text>(find.byKey(const Key('certified-lesson-count')))
            .data,
        '3');
    expect(tester.widget<Text>(find.byKey(const Key('signature-count'))).data,
        '2');
    expect(find.byKey(const ValueKey('badge-lesson-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-lesson-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-lesson-3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('badge-lesson-3')));
    await tester.pumpAndSettle();

    expect(find.text('지수 코치의 시그니처'), findsOneWidget);
    expect(find.text('참여 확인일'), findsOneWidget);
    expect(find.text('2026.09.29'), findsOneWidget);
    expect(find.text('참여 인증 완료'), findsOneWidget);
    expect(find.textContaining('지수 코치가 레슨 참여를 확인하고'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.text('참여 확인일'), findsNothing);
    expect(service.calls, 1);
  });

  testWidgets('live awards update the collection without resubscribing',
      (tester) async {
    final controller = StreamController<List<LessonBadge>>();
    addTearDown(controller.close);
    final service = _BadgeService(() => controller.stream);
    await _showCollection(tester, service);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.add([]);
    await tester.pumpAndSettle();
    expect(find.text('수집된 뱃지가 없습니다.'), findsOneWidget);

    controller.add([_badge('new-lesson')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('badge-new-lesson')), findsOneWidget);
    expect(find.text('수집된 뱃지가 없습니다.'), findsNothing);
    expect(service.calls, 1);
  });

  testWidgets('failed stream can be retried', (tester) async {
    var attempts = 0;
    final service = _BadgeService(() {
      if (attempts++ == 0) {
        return Stream.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      }
      return Stream.value([_badge('after-retry')]);
    });
    await _showCollection(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('뱃지를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('연결 상태를 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('badge-after-retry')), findsOneWidget);
    expect(find.text('뱃지를 불러오지 못했어요'), findsNothing);
    expect(service.calls, 2);
  });

  testWidgets(
      'permission errors are not shown as empty collections or connection failures',
      (tester) async {
    final service = _BadgeService(() => Stream.error(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied')));
    await _showCollection(tester, service);
    await tester.pumpAndSettle();
    expect(find.text('뱃지 조회 권한이 없습니다. 관리자에게 문의해 주세요.'), findsOneWidget);
    expect(find.text('수집된 뱃지가 없습니다.'), findsNothing);
    expect(find.textContaining('연결 상태를 확인'), findsNothing);
  });

  testWidgets('retry returning no badges shows the empty collection',
      (tester) async {
    var attempts = 0;
    final service = _BadgeService(() => attempts++ == 0
        ? Stream.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'))
        : Stream.value([]));
    await _showCollection(tester, service);
    await tester.pumpAndSettle();
    expect(find.textContaining('연결 상태를 확인'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('수집된 뱃지가 없습니다.'), findsOneWidget);
    expect(find.text('레슨 참여 후 시그니처 뱃지를 수집하세요!'), findsOneWidget);
    expect(find.textContaining('연결 상태를 확인'), findsNothing);
  });

  testWidgets('collection and detail fit a narrow screen with enlarged text',
      (tester) async {
    final service = _BadgeService(() => Stream.value([
          _badge('long-label',
              name: '아주 긴 이름을 가진 농구 코치', signature: '수비를 제치는 시그니처 스텝백 점프슛'),
        ]));
    await _showCollection(tester, service,
        size: const Size(320, 640), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('농구 · 참여 인증'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('농구 · 참여 인증'));
    await tester.pumpAndSettle();
    expect(find.text('참여 인증 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
