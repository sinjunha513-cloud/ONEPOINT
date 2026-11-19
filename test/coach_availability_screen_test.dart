import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:onepoint_lesson/models/lesson_slot.dart';
import 'package:onepoint_lesson/screens/my_page_screen.dart';
import 'package:onepoint_lesson/screens/coach_availability_screen.dart';
import 'package:onepoint_lesson/config/onepoint_theme.dart';
import 'package:onepoint_lesson/config/onepoint_design.dart';
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
      {AvailabilityProgress? onProgress}) async {
    saved = ranges;
    onProgress?.call(ranges.length, ranges.length);
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

class _InterruptedService extends _FakeAvailabilityService {
  final attempts = <List<AvailabilityRange>>[];
  @override
  Future<List<String>> saveSlots(List<AvailabilityRange> ranges,
      {AvailabilityProgress? onProgress}) async {
    attempts.add([...ranges]);
    if (attempts.length == 1) {
      throw AvailabilityBatchException(
          savedSlotIds: ['confirmed'],
          remainingRanges: ranges.sublist(1),
          cause: StateError('연결이 끊겼습니다.'));
    }
    return super.saveSlots(ranges, onProgress: onProgress);
  }
}

class _EditableService extends _FakeAvailabilityService {
  _EditableService(this.slot);
  LessonSlot slot;
  final changes = StreamController<List<LessonSlot>>.broadcast();
  final edits = <({String? id, DateTime start, DateTime end})>[];
  @override
  Stream<List<LessonSlot>> mySlots() async* {
    yield [slot];
    yield* changes.stream;
  }

  @override
  Future<String> saveSlot(
      {String? slotId,
      required DateTime startAt,
      required DateTime endAt}) async {
    edits.add((id: slotId, start: startAt, end: endAt));
    slot = LessonSlot(
        id: slotId!,
        coachUid: 'coach',
        startAt: startAt,
        endAt: endAt,
        status: 'available');
    changes.add([slot]);
    return slotId;
  }
}

String _dayKey(DateTime date) =>
    'availability-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Future<void> _openPicker(
    WidgetTester tester, _FakeAvailabilityService service) async {
  await tester.pumpWidget(MaterialApp(
      theme: buildOnepointTheme(),
      home: CoachAvailabilityScreen(service: service)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('여러 날짜 · 시간 추가'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder,
    {double step = 300}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, step,
        scrollable: find.byType(Scrollable).first);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'registered all-day slot can change date and time repeatedly with the same ID',
      (tester) async {
    final start = DateTime.utc(2036, 1, 9, 15);
    final service = _EditableService(LessonSlot(
        id: 'bulk-registered',
        coachUid: 'coach',
        startAt: start,
        endAt: start.add(const Duration(days: 1)),
        status: 'available'));
    addTearDown(service.changes.close);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: buildOnepointTheme(),
        home: CoachAvailabilityScreen(service: service)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('edit-availability-bulk-registered')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-edited-availability')));
    await tester.pumpAndSettle();
    expect(service.edits.single.end.difference(service.edits.single.start),
        const Duration(days: 1));
    await tester
        .tap(find.byKey(const ValueKey('availability-slot-bulk-registered')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-availability-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    for (final e in [('start', '09', '30'), ('end', '10', '30')]) {
      await tester.tap(find.byKey(ValueKey('edit-availability-${e.$1}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), e.$2);
      await tester.enterText(find.byType(TextField).at(1), e.$3);
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('save-edited-availability')));
    await tester.pumpAndSettle();
    expect(service.edits, hasLength(2));
    expect(service.edits.every((e) => e.id == 'bulk-registered'), isTrue);
    expect(toKoreaTime(service.slot.startAt), DateTime.utc(2036, 1, 11, 9, 30));
    expect(service.slot.endAt.difference(service.slot.startAt),
        const Duration(hours: 1));
    expect(find.byKey(const ValueKey('availability-slot-bulk-registered')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'custom start time and retry retain only the unconfirmed selection',
      (tester) async {
    final service = _InterruptedService();
    await _openPicker(tester, service);
    final now = koreaNow();
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    for (var day = 1; day <= 2; day++) {
      await _tapVisible(
          tester,
          find.byKey(
              ValueKey(_dayKey(DateTime(now.year, now.month + 1, day)))));
    }
    await _tapVisible(tester, find.text('시간 직접 입력'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '09');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('availability-time-555')))
            .selected,
        isTrue);
    await tester.tap(find.byKey(const ValueKey('save-bulk-availability')));
    await tester.pumpAndSettle();
    expect(find.text('총 2개 중 1개 등록'), findsOneWidget);
    await tester.tap(find.text('남은 1개 다시 등록'));
    await tester.pumpAndSettle();
    expect(service.attempts.map((a) => a.length), [2, 1]);
    expect(service.attempts.last.single, service.attempts.first.last);
    expect(find.text('레슨 가능 시간 2개를 등록했습니다.'), findsOneWidget);
  });

  testWidgets(
      'month presets replace only the visible month and retain other dates',
      (tester) async {
    final service = _FakeAvailabilityService();
    await _openPicker(tester, service);
    final today = koreaNow();
    final month = DateTime(today.year, today.month + 1);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    await _tapVisible(
        tester, find.byKey(const ValueKey('availability-month-all')));
    await _tapVisible(
        tester, find.byKey(const ValueKey('availability-month-weekends')));
    final weekends = [
      for (var day = 1;
          day <= DateUtils.getDaysInMonth(month.year, month.month);
          day++)
        if (DateTime(month.year, month.month, day).weekday >= 6)
          DateTime(month.year, month.month, day)
    ];
    expect(find.text('${weekends.length}일 선택'), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('다음 달'), step: -300);
    final extra = DateTime(month.year, month.month + 1, 1);
    await _tapVisible(tester, find.byKey(ValueKey(_dayKey(extra))));
    await _tapVisible(
        tester, find.byKey(const ValueKey('availability-time-0')));
    await tester.tap(find.byKey(const ValueKey('save-bulk-availability')));
    await tester.pumpAndSettle();
    expect(
        service.saved.map((r) {
          final day = toKoreaTime(r.startAt);
          return DateTime(day.year, day.month, day.day);
        }).toSet(),
        {...weekends, extra});
  });

  testWidgets(
      'full month and all-day times can register more than 100 selections',
      (tester) async {
    final service = _FakeAvailabilityService();
    await _openPicker(tester, service);
    final now = koreaNow();
    final month = DateTime(now.year, now.month + 1);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    await _tapVisible(
        tester, find.byKey(const ValueKey('availability-month-all')));
    await _tapVisible(tester, find.text('시간 전체 선택'));
    final count = DateUtils.getDaysInMonth(month.year, month.month) * 24;
    expect(find.text('선택한 가능 시간 $count개 등록'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-bulk-availability')));
    await tester.pumpAndSettle();
    expect(service.saved, hasLength(count));
    expect(toKoreaTime(service.saved.first.startAt).hour, 0);
    expect(toKoreaTime(service.saved.last.startAt).hour, 23);
  });

  testWidgets(
      'dates beyond two years and custom durations crossing midnight are supported',
      (tester) async {
    final service = _FakeAvailabilityService();
    await _openPicker(tester, service);
    final now = koreaNow();
    final date = DateTime(now.year, now.month + 25, 10);
    for (var month = 0; month < 25; month++) {
      await tester.tap(find.byTooltip('다음 달'));
      await tester.pump();
    }
    await _tapVisible(tester, find.byKey(ValueKey(_dayKey(date))));
    await _tapVisible(tester, find.text('길이 직접 입력'));
    await tester.enterText(
        find.byKey(const ValueKey('availability-custom-duration')), '45');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    await _tapVisible(
        tester, find.byKey(const ValueKey('availability-time-1410')));
    await tester.tap(find.byKey(const ValueKey('save-bulk-availability')));
    await tester.pumpAndSettle();
    final saved = service.saved.single;
    expect(toKoreaTime(saved.startAt),
        DateTime.utc(date.year, date.month, 10, 23, 30));
    expect(toKoreaTime(saved.endAt),
        DateTime.utc(date.year, date.month, 11, 0, 15));
  });

  testWidgets('마이페이지 날짜 등록 카드에서 여러 날짜와 시간을 등록한다', (tester) async {
    final service = _FakeAvailabilityService();
    final db = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'coach'));
    await db
        .collection('users')
        .doc('coach')
        .set({'name': '테스트 코치', 'role': 'coach'});
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOnepointTheme(),
        home: MyPageScreen(
            firestore: db, auth: auth, availabilityService: service),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('my-availability-card'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
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
      final day = find.byKey(ValueKey(_dayKey(date)));
      await tester.ensureVisible(day);
      await tester.pumpAndSettle();
      await tester.tap(day);
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
      expect(chip.backgroundColor, OnepointDesign.surface);
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
