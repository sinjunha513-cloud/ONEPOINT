import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/models/lesson_slot.dart';
import 'package:onepoint_lesson/screens/coach_availability_screen.dart';
import 'package:onepoint_lesson/services/coach_availability_service.dart';
import 'package:onepoint_lesson/utils/korea_time.dart';

class _FakeAvailabilityService implements CoachAvailabilityService {
  List<({DateTime startAt, DateTime endAt})> saved = const [];

  @override
  String get currentUid => 'coach';

  @override
  Stream<List<LessonSlot>> mySlots() => Stream.value(const []);

  @override
  Stream<List<LessonSlot>> slotsForCoach(
    String coachUid, {
    bool availableOnly = false,
  }) =>
      Stream.value(const []);

  @override
  Future<String> saveSlot({
    String? slotId,
    required DateTime startAt,
    required DateTime endAt,
  }) async =>
      slotId ?? 'slot';

  @override
  Future<List<String>> saveSlots(
    List<({DateTime startAt, DateTime endAt})> ranges,
  ) async {
    saved = ranges;
    return List.generate(ranges.length, (index) => 'slot-$index');
  }

  @override
  Future<void> deleteSlot(String slotId) async {}

  @override
  Future<void> rescheduleLesson(String lessonId, String slotId) async {}

  @override
  Stream<List<LessonScheduleChange>> scheduleHistory(String lessonId) =>
      Stream.value(const []);
}

String _dayKey(DateTime date) =>
    'availability-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

void main() {
  testWidgets('여러 날짜와 여러 시간 버튼을 한 번에 등록한다', (tester) async {
    final service = _FakeAvailabilityService();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: CoachAvailabilityScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('여러 날짜 · 시간 추가'));
    await tester.pumpAndSettle();

    final now = koreaNow();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateUtils.getDaysInMonth(today.year, today.month);
    final dates = today.day <= lastDay - 2
        ? [
            today.add(const Duration(days: 1)),
            today.add(const Duration(days: 2))
          ]
        : [
            DateTime(today.year, today.month + 1, 1),
            DateTime(today.year, today.month + 1, 2),
          ];
    if (dates.first.month != today.month) {
      await tester.tap(find.byTooltip('다음 달'));
      await tester.pumpAndSettle();
    }
    for (final date in dates) {
      await tester.tap(find.byKey(ValueKey(_dayKey(date))));
      await tester.pump();
    }

    for (final minute in const [9 * 60, 10 * 60]) {
      final finder = find.byKey(ValueKey('availability-time-$minute'));
      await tester.scrollUntilVisible(
        finder,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      final chip = tester.widget<ChoiceChip>(finder);
      expect(chip.backgroundColor, const Color(0xFF222936));
      expect(chip.labelStyle?.color, Colors.white);
      await tester.tap(finder);
      await tester.pump();
    }

    expect(find.text('선택한 가능 시간 4개 등록'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-bulk-availability')));
    await tester.pumpAndSettle();

    expect(service.saved, hasLength(4));
    expect(
      service.saved.every(
        (range) => range.endAt.difference(range.startAt).inMinutes == 60,
      ),
      isTrue,
    );
    expect(find.text('레슨 가능 시간 4개를 등록했습니다.'), findsOneWidget);
  });
}
