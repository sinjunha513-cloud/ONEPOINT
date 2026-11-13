import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/sports.dart';
import 'package:onepoint_lesson/widget/lesson_badge_emblem.dart';

void main() {
  Future<void> showBadge(WidgetTester tester, String sport) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonBadgeEmblem(identity: '기술', sport: sport),
          ),
        ),
      );

  testWidgets('every supported sport has its own representative badge mark',
      (tester) async {
    for (final sport in supportedSports) {
      await showBadge(tester, sport);
      expect(find.byKey(ValueKey('sport-mark-$sport')), findsOneWidget,
          reason: '$sport 뱃지 아이콘이 필요합니다.');
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
      if (sport != '축구') {
        expect(find.byIcon(Icons.sports_soccer), findsNothing,
            reason: '$sport 뱃지가 축구공으로 표시되면 안 됩니다.');
      }
    }

    await showBadge(tester, '축구');
    expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
    await showBadge(tester, '농구');
    expect(find.byIcon(Icons.sports_basketball), findsOneWidget);
    await showBadge(tester, '배드민턴');
    expect(find.text('🏸'), findsOneWidget);
    await showBadge(tester, '클라이밍');
    expect(find.text('🧗'), findsOneWidget);
    await showBadge(tester, '유도');
    expect(find.text('🥋'), findsOneWidget);
    await showBadge(tester, '탁구');
    expect(find.text('🏓'), findsOneWidget);
  });

  testWidgets('missing sport uses a neutral medal rather than lightning',
      (tester) async {
    await showBadge(tester, '');

    expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
  });
}
