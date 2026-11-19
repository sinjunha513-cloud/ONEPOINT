import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/onepoint_design.dart';

import '../models/lesson_slot.dart';
import '../services/coach_availability_service.dart';
import '../utils/korea_time.dart';

class CoachAvailabilityScreen extends StatefulWidget {
  const CoachAvailabilityScreen({super.key, this.service});

  final CoachAvailabilityService? service;

  @override
  State<CoachAvailabilityScreen> createState() =>
      _CoachAvailabilityScreenState();
}

class _CoachAvailabilityScreenState extends State<CoachAvailabilityScreen> {
  late final CoachAvailabilityService _service =
      widget.service ?? CoachAvailabilityService();
  final Set<String> _busy = <String>{};
  List<AvailabilityRange>? _retryRanges;
  int _completed = 0;
  int _total = 0;
  String? _saveError;

  Future<void> _addMany() async {
    final ranges = await Navigator.push<List<_SlotRange>>(
      context,
      MaterialPageRoute(builder: (_) => const _BulkAvailabilityScreen()),
    );
    if (ranges == null || ranges.isEmpty || !mounted) return;
    await _registerRanges([
      for (final range in ranges) (startAt: range.startAt, endAt: range.endAt)
    ]);
  }

  Future<void> _registerRanges(List<AvailabilityRange> ranges,
      {int previous = 0}) async {
    if (_busy.contains('bulk')) return;
    setState(() {
      _busy.add('bulk');
      _retryRanges = null;
      _saveError = null;
      _completed = previous;
      _total = previous + ranges.length;
    });
    try {
      final ids = await _service.saveSlots(ranges, onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _completed = previous + done;
            _total = previous + total;
          });
        }
      });
      if (!mounted) return;
      setState(() {
        _completed = previous + ids.length;
        _total = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('레슨 가능 시간 ${previous + ids.length}개를 등록했습니다.')));
    } on AvailabilityBatchException catch (error) {
      if (!mounted) return;
      setState(() {
        _completed = previous + error.savedSlotIds.length;
        _retryRanges = error.remainingRanges;
        _saveError = availabilityError(error.cause);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _retryRanges = ranges;
        _saveError = availabilityError(error);
      });
    } finally {
      if (mounted) setState(() => _busy.remove('bulk'));
    }
  }

  Widget _registrationStatus() => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: OnepointDesign.surface,
            borderRadius: BorderRadius.circular(16)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('총 $_total개 중 $_completed개 등록',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: _total == 0 ? 0 : _completed / _total,
              color: OnepointDesign.lime,
              backgroundColor: Colors.white12),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!,
                style: const TextStyle(color: Colors.orangeAccent)),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: () =>
                    _registerRanges(_retryRanges!, previous: _completed),
                child: Text('남은 ${_retryRanges?.length ?? 0}개 다시 등록')),
            TextButton(
                onPressed: () => setState(() {
                      _retryRanges = null;
                      _saveError = null;
                      _total = 0;
                    }),
                child: const Text('남은 선택 취소')),
          ],
        ]),
      );

  Future<void> _edit([LessonSlot? slot]) async {
    final range = await showDialog<_SlotRange>(
      context: context,
      builder: (_) => _SlotEditorDialog(slot: slot),
    );
    if (range == null || !mounted) return;
    final key = slot?.id ?? 'new';
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await _service.saveSlot(
        slotId: slot?.id,
        startAt: range.startAt,
        endAt: range.endAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(slot == null ? '레슨 가능 시간을 등록했습니다.' : '레슨 가능 시간을 수정했습니다.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(availabilityError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _delete(LessonSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('가능 시간 삭제'),
        content:
            Text('${formatKoreaTimeRange(slot.startAt, slot.endAt)}을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy.contains(slot.id)) return;
    setState(() => _busy.add(slot.id));
    try {
      await _service.deleteSlot(slot.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(availabilityError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(slot.id));
    }
  }

  String _status(LessonSlot slot) {
    if (!slot.isFuture && slot.status == 'available') return '지난 시간';
    return switch (slot.status) {
      'available' => '신청 가능',
      'booked' => '예약됨',
      'completed' => '완료',
      _ => '확인 필요',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('레슨 가능 시간 관리'), actions: [
          IconButton(
              tooltip: '시간 직접 추가',
              onPressed: _busy.contains('bulk') || _retryRanges != null
                  ? null
                  : () => _edit(),
              icon: const Icon(Icons.add_rounded))
        ]),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: OnepointDesign.lime,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onPressed: _busy.contains('bulk')
              ? null
              : _retryRanges != null
                  ? () => _registerRanges(_retryRanges!, previous: _completed)
                  : _addMany,
          icon: _busy.contains('bulk')
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calendar_month_rounded),
          label: Text(_busy.contains('bulk')
              ? '등록 중 $_completed/$_total'
              : _retryRanges != null
                  ? '남은 일정 다시 등록'
                  : '여러 날짜 · 시간 추가'),
        ),
        body: Column(children: [
          if (_busy.contains('bulk') || _retryRanges != null)
            _registrationStatus(),
          Expanded(
              child: StreamBuilder<List<LessonSlot>>(
            stream: _service.mySlots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 42),
                        const SizedBox(height: 12),
                        Text(availabilityError(snapshot.error!)),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final slots = snapshot.data!;
              if (slots.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      '등록된 레슨 가능 시간이 없습니다.\n아래 버튼으로 수강생이 선택할 날짜와 시간을 추가해 주세요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '한국 시간(KST) 기준입니다. 아래 버튼에서 가능한 날짜와 시간대를 한꺼번에 선택할 수 있습니다. 예약된 시간은 내 레슨에서 변경해 주세요.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final slot in slots)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          slot.status == 'available'
                              ? Icons.event_available_rounded
                              : Icons.event_busy_rounded,
                          color: slot.status == 'available'
                              ? Colors.lightGreenAccent
                              : Colors.orangeAccent,
                        ),
                        title: Text(
                            formatKoreaTimeRange(slot.startAt, slot.endAt)),
                        subtitle: Text(_status(slot)),
                        trailing: _busy.contains(slot.id)
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : slot.status == 'available'
                                ? PopupMenuButton<String>(
                                    onSelected: (value) => value == 'edit'
                                        ? _edit(slot)
                                        : _delete(slot),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit', child: Text('수정')),
                                      PopupMenuItem(
                                          value: 'delete', child: Text('삭제')),
                                    ],
                                  )
                                : const Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                ],
              );
            },
          )),
        ]),
      );
}

enum _MonthSelection { all, weekdays, weekends }

class _BulkAvailabilityScreen extends StatefulWidget {
  const _BulkAvailabilityScreen();
  @override
  State<_BulkAvailabilityScreen> createState() =>
      _BulkAvailabilityScreenState();
}

class _BulkAvailabilityScreenState extends State<_BulkAvailabilityScreen> {
  final Set<DateTime> _selectedDates = {};
  final Set<int> _selectedStartMinutes = {};
  final Set<int> _customStartMinutes = {};
  late DateTime _visibleMonth;
  int _durationMinutes = 60;
  String? _error;
  DateTime get _today {
    final now = koreaNow();
    return DateTime(now.year, now.month, now.day);
  }

  // Firestore/Material date representation, rather than an arbitrary horizon.
  DateTime get _lastDate => DateTime(9999, 12, 31);

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_today.year, _today.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
  bool _selectable(DateTime date) =>
      !date.isBefore(_today) && !date.isAfter(_lastDate);
  void _toggleDate(DateTime date) {
    if (!_selectable(date)) return;
    setState(() {
      if (!_selectedDates.add(date)) _selectedDates.remove(date);
      _error = null;
    });
  }

  List<DateTime> _monthDates(_MonthSelection preset) => [
        for (var day = 1;
            day <=
                DateUtils.getDaysInMonth(
                    _visibleMonth.year, _visibleMonth.month);
            day++)
          if (_selectable(
                  DateTime(_visibleMonth.year, _visibleMonth.month, day)) &&
              (preset == _MonthSelection.all ||
                  (preset == _MonthSelection.weekdays
                      ? DateTime(_visibleMonth.year, _visibleMonth.month, day)
                              .weekday <=
                          5
                      : DateTime(_visibleMonth.year, _visibleMonth.month, day)
                              .weekday >=
                          6)))
            DateTime(_visibleMonth.year, _visibleMonth.month, day),
      ];
  bool _presetSelected(_MonthSelection preset) {
    final expected = _monthDates(preset).toSet();
    final actual =
        _selectedDates.where((date) => _sameMonth(date, _visibleMonth)).toSet();
    return expected.isNotEmpty &&
        actual.length == expected.length &&
        actual.containsAll(expected);
  }

  void _selectVisibleMonth(_MonthSelection preset) => setState(() {
        // Replace only this month's selection, retaining choices in other months.
        _selectedDates.removeWhere((date) => _sameMonth(date, _visibleMonth));
        _selectedDates.addAll(_monthDates(preset));
        _error = null;
      });
  void _changeMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    if (next.isBefore(DateTime(_today.year, _today.month)) ||
        next.isAfter(DateTime(9999, 12))) {
      return;
    }
    setState(() => _visibleMonth = next);
  }

  Future<void> _jumpToDate() async {
    final picked = await showDatePicker(
        context: context,
        firstDate: _today,
        lastDate: _lastDate,
        initialDate: _visibleMonth.isBefore(_today) ? _today : _visibleMonth,
        helpText: '원하는 날짜로 이동 (KST)',
        builder: (context, child) =>
            Theme(data: _availabilityPickerTheme(context), child: child!));
    if (picked == null || !mounted) return;
    setState(() {
      _visibleMonth = DateTime(picked.year, picked.month);
      _selectedDates.add(picked);
      _error = null;
    });
  }

  List<int> get _startMinutes => (<int>{
        for (var m = 0; m < 1440; m += 30) m,
        ..._customStartMinutes,
        ..._selectedStartMinutes,
      }.toList()
        ..sort());
  String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  bool _conflicts(int start) => _selectedStartMinutes.any((other) =>
      other != start &&
      other < start + _durationMinutes &&
      start < other + _durationMinutes);
  void _toggleStart(int minutes) => setState(() {
        if (_selectedStartMinutes.contains(minutes)) {
          _selectedStartMinutes.remove(minutes);
        } else if (_conflicts(minutes)) {
          _error = '이미 선택한 시간과 겹칩니다. 겹치는 시간을 먼저 해제해 주세요.';
          return;
        } else {
          _selectedStartMinutes.add(minutes);
        }
        _error = null;
      });
  void _setDuration(int minutes) => setState(() {
        _durationMinutes = minutes;
        _selectedStartMinutes.clear();
        _error = null;
      });
  Future<void> _customTime() async {
    final value = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 9, minute: 0),
        initialEntryMode: TimePickerEntryMode.input,
        helpText: '시작 시간 직접 선택 (KST)',
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child:
                Theme(data: _availabilityPickerTheme(context), child: child!)));
    if (value == null || !mounted) return;
    final minutes = value.hour * 60 + value.minute;
    setState(() => _customStartMinutes.add(minutes));
    if (!_selectedStartMinutes.contains(minutes)) _toggleStart(minutes);
  }

  Future<void> _customDuration() async {
    final value = await showDialog<int>(
        context: context,
        builder: (_) => _DurationDialog(initialMinutes: _durationMinutes));
    if (value != null && mounted) _setDuration(value);
  }

  void _allTimes() => setState(() {
        _selectedStartMinutes.clear();
        for (var minute = 0;
            minute + _durationMinutes <= 1440;
            minute += _durationMinutes) {
          _selectedStartMinutes.add(minute);
        }
        _error = null;
      });
  List<_SlotRange> _ranges() {
    final now = DateTime.now().toUtc();
    final result = <_SlotRange>[];
    for (final date in _selectedDates) {
      for (final minute in _selectedStartMinutes) {
        final start =
            koreaComponentsToUtc(date, hour: minute ~/ 60, minute: minute % 60);
        if (start.isAfter(now)) {
          result.add(_SlotRange(
              start, start.add(Duration(minutes: _durationMinutes))));
        }
      }
    }
    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result;
  }

  void _submit() {
    final ranges = _ranges();
    if (ranges.isEmpty) {
      setState(() => _error = '날짜와 시작 시간을 선택해 주세요. 지난 시간은 등록되지 않습니다.');
      return;
    }
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].startAt.isBefore(ranges[i - 1].endAt)) {
        setState(() => _error = '선택한 일정이 서로 겹칩니다. 다음 날 시간과 수업 길이를 확인해 주세요.');
        return;
      }
    }
    Navigator.pop(context, ranges);
  }

  @override
  Widget build(BuildContext context) {
    final ranges = _ranges(),
        skipped = _selectedDates.length * _selectedStartMinutes.length -
            ranges.length;
    return Scaffold(
      backgroundColor: OnepointDesign.background,
      appBar: AppBar(title: const Text('가능 날짜 · 시간 선택')),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const _StepTitle(
                            number: '1',
                            title: '가능한 날짜를 선택하세요',
                            description:
                                '여러 달의 날짜를 함께 선택할 수 있어요. 시간은 한국 시간(KST) 기준입니다.'),
                        const SizedBox(height: 18),
                        _calendarCard(),
                        const SizedBox(height: 12),
                        Row(children: [
                          for (final entry in const [
                            (_MonthSelection.all, '이달 전체'),
                            (_MonthSelection.weekdays, '이달 평일'),
                            (_MonthSelection.weekends, '이달 주말')
                          ])
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    child: OutlinedButton(
                                      key: ValueKey(
                                          'availability-month-${entry.$1.name}'),
                                      style: OutlinedButton.styleFrom(
                                          backgroundColor:
                                              _presetSelected(entry.$1)
                                                  ? OnepointDesign.lime
                                                  : OnepointDesign.surface,
                                          foregroundColor:
                                              _presetSelected(entry.$1)
                                                  ? Colors.black
                                                  : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 14),
                                          side: BorderSide(
                                              color: _presetSelected(entry.$1)
                                                  ? OnepointDesign.lime
                                                  : Colors.white12)),
                                      onPressed: () =>
                                          _selectVisibleMonth(entry.$1),
                                      child: Text(entry.$2,
                                          style: const TextStyle(fontSize: 12)),
                                    ))),
                        ]),
                        Row(children: [
                          Expanded(
                              child: Text('${_selectedDates.length}일 선택',
                                  style: const TextStyle(
                                      color: OnepointDesign.lime,
                                      fontWeight: FontWeight.w600))),
                          TextButton(
                              onPressed: _selectedDates.isEmpty
                                  ? null
                                  : () => setState(() {
                                        _selectedDates.clear();
                                        _error = null;
                                      }),
                              child: const Text('날짜 초기화'))
                        ]),
                        const SizedBox(height: 22),
                        const _StepTitle(
                            number: '2',
                            title: '수업 길이를 선택하세요',
                            description: '수업 길이를 바꾸면 시작 시간을 다시 선택합니다.'),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final duration in [
                            30,
                            60,
                            90,
                            120,
                            if (![30, 60, 90, 120].contains(_durationMinutes))
                              _durationMinutes
                          ])
                            _choice(
                                'availability-duration-$duration',
                                '$duration분',
                                _durationMinutes == duration,
                                () => _setDuration(duration)),
                          OutlinedButton(
                              onPressed: _customDuration,
                              child: const Text('길이 직접 입력')),
                        ]),
                        const SizedBox(height: 28),
                        const _StepTitle(
                            number: '3',
                            title: '시작 시간을 선택하세요',
                            description: '하루 전체 시간대에서 선택하거나 원하는 시각을 직접 입력하세요.'),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                              onPressed: _allTimes,
                              icon:
                                  const Icon(Icons.done_all_rounded, size: 18),
                              label: const Text('시간 전체 선택')),
                          OutlinedButton.icon(
                              onPressed: _customTime,
                              icon:
                                  const Icon(Icons.schedule_rounded, size: 18),
                              label: const Text('시간 직접 입력')),
                          TextButton(
                              onPressed: _selectedStartMinutes.isEmpty
                                  ? null
                                  : () => setState(() {
                                        _selectedStartMinutes.clear();
                                        _error = null;
                                      }),
                              child: const Text('시간 초기화')),
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final minute in _startMinutes)
                            _choice(
                                'availability-time-$minute',
                                _clock(minute),
                                _selectedStartMinutes.contains(minute),
                                () => _toggleStart(minute),
                                enabled: !_conflicts(minute))
                        ]),
                        const SizedBox(height: 16),
                        Text(
                            '${_selectedStartMinutes.length}개 시간 선택 · 총 ${ranges.length}개 일정',
                            style: const TextStyle(
                                color: OnepointDesign.lime,
                                fontWeight: FontWeight.w600)),
                        if (skipped > 0)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('이미 지난 시간 $skipped개는 제외됩니다.',
                                  style: const TextStyle(
                                      color: OnepointDesign.muted,
                                      fontSize: 12))),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.orangeAccent))),
                      ],
                    )))),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
                color: OnepointDesign.background,
                border: Border(top: BorderSide(color: Colors.white12))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  key: const ValueKey('save-bulk-availability'),
                  onPressed: ranges.isEmpty ? null : _submit,
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text('선택한 가능 시간 ${ranges.length}개 등록')),
            )),
      ])),
    );
  }

  Widget _choice(String key, String label, bool selected, VoidCallback onTap,
          {bool enabled = true}) =>
      ChoiceChip(
        key: ValueKey(key),
        selected: selected,
        showCheckmark: false,
        selectedColor: OnepointDesign.lime,
        backgroundColor: OnepointDesign.surface,
        disabledColor: OnepointDesign.surface,
        side:
            BorderSide(color: selected ? OnepointDesign.lime : Colors.white12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['Pretendard'],
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.black
                : enabled
                    ? Colors.white
                    : Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        label: Text(label),
        onSelected: selected || enabled ? (_) => onTap() : null,
      );
  Widget _calendarCard() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month),
        days =
            DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final leading = first.weekday - 1,
        cells = ((first.weekday - 1 + days + 6) ~/ 7) * 7;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: OnepointDesign.surface,
            borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: '이전 달',
                onPressed:
                    _visibleMonth.isAfter(DateTime(_today.year, _today.month))
                        ? () => _changeMonth(-1)
                        : null,
                icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
                child: Tooltip(
                    message: '원하는 날짜로 이동',
                    child: TextButton(
                        onPressed: _jumpToDate,
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero),
                        child: Text(
                            '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600))))),
            IconButton(
                tooltip: '다음 달',
                onPressed: _visibleMonth.year < 9999 || _visibleMonth.month < 12
                    ? () => _changeMonth(1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                  child: Text(const ['월', '화', '수', '목', '금', '토', '일'][i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          color: i >= 5
                              ? OnepointDesign.blue
                              : OnepointDesign.muted)))
          ]),
          const SizedBox(height: 10),
          GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6),
              itemBuilder: (context, index) {
                final day = index - leading + 1;
                if (day < 1 || day > days) return const SizedBox.shrink();
                final date =
                        DateTime(_visibleMonth.year, _visibleMonth.month, day),
                    selected = _selectedDates.contains(
                        DateTime(_visibleMonth.year, _visibleMonth.month, day));
                final enabled = _selectable(date),
                    today = _sameDay(date, _today);
                final dateKey =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                return Semantics(
                    label: '${date.year}년 ${date.month}월 $day일',
                    selected: selected,
                    enabled: enabled,
                    button: true,
                    child: Material(
                        color:
                            selected ? OnepointDesign.lime : Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: today
                                    ? OnepointDesign.blue
                                    : Colors.transparent)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                            key: ValueKey('availability-day-$dateKey'),
                            onTap: enabled ? () => _toggleDate(date) : null,
                            child: Center(
                                child: Text('$day',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: selected
                                            ? Colors.black
                                            : !enabled
                                                ? Colors.white24
                                                : date.weekday >= 6
                                                    ? OnepointDesign.blue
                                                    : Colors.white))))));
              }),
        ]));
  }
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({required this.initialMinutes});
  final int initialMinutes;
  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _controller =
      TextEditingController(text: '${widget.initialMinutes}');
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_controller.text);
    if (value == null || value < 1 || value > 1440) {
      setState(() => _error = '수업 길이는 1~1440분으로 입력해 주세요.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('수업 길이 직접 입력'),
          content: TextField(
              key: const ValueKey('availability-custom-duration'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              decoration: InputDecoration(
                  labelText: '수업 길이 (분)', hintText: '예: 45', errorText: _error),
              onSubmitted: (_) => _save()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기')),
            FilledButton(onPressed: _save, child: const Text('적용'))
          ]);
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: OnepointDesign.lime,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: OnepointDesign.background,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      );
}

class _SlotRange {
  const _SlotRange(this.startAt, this.endAt);
  final DateTime startAt;
  final DateTime endAt;
}

class _SlotEditorDialog extends StatefulWidget {
  const _SlotEditorDialog({this.slot});
  final LessonSlot? slot;

  @override
  State<_SlotEditorDialog> createState() => _SlotEditorDialogState();
}

class _SlotEditorDialogState extends State<_SlotEditorDialog> {
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = koreaNow();
    final start = widget.slot == null
        ? DateTime(now.year, now.month, now.day, now.hour + 1)
        : toKoreaTime(widget.slot!.startAt);
    final end = widget.slot == null
        ? start.add(const Duration(hours: 1))
        : toKoreaTime(widget.slot!.endAt);
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = TimeOfDay(hour: end.hour, minute: end.minute);
  }

  Future<void> _pickDate() async {
    final todayKorea = koreaNow();
    final today = DateTime(todayKorea.year, todayKorea.month, todayKorea.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(9999, 12, 31),
      helpText: '레슨 가능 날짜 선택 (KST)',
      builder: (context, child) => Theme(
        data: _availabilityPickerTheme(context),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      helpText: start ? '시작 시간 (KST)' : '종료 시간 (KST)',
      builder: (context, child) => Theme(
        data: _availabilityPickerTheme(context),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  void _submit() {
    final startAt = koreaComponentsToUtc(
      _date,
      hour: _start.hour,
      minute: _start.minute,
    );
    var endAt = koreaComponentsToUtc(
      _date,
      hour: _end.hour,
      minute: _end.minute,
    );
    if (endAt.isBefore(startAt)) endAt = endAt.add(const Duration(days: 1));
    if (!endAt.isAfter(startAt)) {
      setState(() => _error = '종료 시간은 시작 시간보다 늦어야 합니다.');
      return;
    }
    if (!startAt.isAfter(DateTime.now().toUtc())) {
      setState(() => _error = '지난 날짜와 시간은 등록할 수 없습니다.');
      return;
    }
    Navigator.pop(context, _SlotRange(startAt, endAt));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: OnepointDesign.surface,
        surfaceTintColor: OnepointDesign.surface,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        title: Text(widget.slot == null ? '가능 시간 추가' : '가능 시간 수정'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('한국 시간(KST) 기준입니다. 종료가 시작보다 이르면 다음 날 종료로 등록됩니다.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(formatKoreaDate(_date)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(true),
                      child: Text('시작 ${_start.format(context)}'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–'),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(false),
                      child: Text('종료 ${_end.format(context)}'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          FilledButton(onPressed: _submit, child: const Text('저장')),
        ],
      );
}

ThemeData _availabilityPickerTheme(BuildContext context) {
  final base = Theme.of(context);
  const colors = ColorScheme.dark(
    primary: OnepointDesign.lime,
    onPrimary: OnepointDesign.background,
    surface: OnepointDesign.surface,
    onSurface: Colors.white,
    outline: Color(0xFF64748B),
  );
  return base.copyWith(
    colorScheme: colors,
    dialogTheme: const DialogThemeData(
      backgroundColor: OnepointDesign.surface,
      surfaceTintColor: OnepointDesign.surface,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: OnepointDesign.surface,
      hourMinuteColor: OnepointDesign.background,
      hourMinuteTextColor: Colors.white,
      dialBackgroundColor: OnepointDesign.background,
      dialHandColor: OnepointDesign.lime,
      dialTextColor: Colors.white,
      entryModeIconColor: OnepointDesign.blue,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: OnepointDesign.surface,
      surfaceTintColor: OnepointDesign.surface,
      headerBackgroundColor: OnepointDesign.background,
      headerForegroundColor: Colors.white,
      weekdayStyle: const TextStyle(color: Colors.white70),
      dayForegroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : states.contains(WidgetState.disabled)
                  ? Colors.white24
                  : Colors.white),
      yearForegroundColor: WidgetStateColor.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.black : Colors.white),
    ),
  );
}
