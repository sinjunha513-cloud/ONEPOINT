import 'package:flutter/material.dart';

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

  Future<void> _addMany() async {
    final ranges = await Navigator.push<List<_SlotRange>>(
      context,
      MaterialPageRoute(builder: (_) => const _BulkAvailabilityScreen()),
    );
    if (ranges == null || ranges.isEmpty || !mounted) return;
    const key = 'bulk';
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final ids = await _service.saveSlots([
        for (final range in ranges)
          (startAt: range.startAt, endAt: range.endAt),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('레슨 가능 시간 ${ids.length}개를 등록했습니다.')),
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
        appBar: AppBar(title: const Text('레슨 가능 시간 관리')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy.contains('bulk') ? null : _addMany,
          icon: _busy.contains('bulk')
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calendar_month_rounded),
          label: const Text('여러 날짜 · 시간 추가'),
        ),
        body: StreamBuilder<List<LessonSlot>>(
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
                      title:
                          Text(formatKoreaTimeRange(slot.startAt, slot.endAt)),
                      subtitle: Text(_status(slot)),
                      trailing: _busy.contains(slot.id)
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
        ),
      );
}

class _BulkAvailabilityScreen extends StatefulWidget {
  const _BulkAvailabilityScreen();

  @override
  State<_BulkAvailabilityScreen> createState() =>
      _BulkAvailabilityScreenState();
}

class _BulkAvailabilityScreenState extends State<_BulkAvailabilityScreen> {
  final Set<DateTime> _selectedDates = <DateTime>{};
  final Set<int> _selectedStartMinutes = <int>{};
  late DateTime _visibleMonth;
  int _durationMinutes = 60;
  String? _error;

  DateTime get _today {
    final now = koreaNow();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _lastDate => _today.add(const Duration(days: 730));

  @override
  void initState() {
    super.initState();
    final today = _today;
    _visibleMonth = DateTime(today.year, today.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _selected(DateTime date) =>
      _selectedDates.any((candidate) => _sameDay(candidate, date));

  bool _selectable(DateTime date) =>
      !date.isBefore(_today) && !date.isAfter(_lastDate);

  void _toggleDate(DateTime date) {
    if (!_selectable(date)) return;
    setState(() {
      final existing = _selectedDates
          .where((candidate) => _sameDay(candidate, date))
          .firstOrNull;
      if (existing == null) {
        _selectedDates.add(DateTime(date.year, date.month, date.day));
      } else {
        _selectedDates.remove(existing);
      }
      _error = null;
    });
  }

  void _selectVisibleMonth({required bool weekdaysOnly}) {
    final days = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    setState(() {
      for (var day = 1; day <= days; day += 1) {
        final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
        if (_selectable(date) && (!weekdaysOnly || date.weekday <= 5)) {
          _selectedDates.add(date);
        }
      }
      _error = null;
    });
  }

  void _changeMonth(int delta) {
    final next = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + delta,
    );
    final earliest = DateTime(_today.year, _today.month);
    final latest = DateTime(_lastDate.year, _lastDate.month);
    if (next.isBefore(earliest) || next.isAfter(latest)) return;
    setState(() => _visibleMonth = next);
  }

  List<int> get _startMinutes {
    final result = <int>[];
    for (var minute = 6 * 60;
        minute + _durationMinutes <= 24 * 60;
        minute += _durationMinutes) {
      result.add(minute);
    }
    return result;
  }

  String _clock(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  void _setDuration(int minutes) {
    setState(() {
      _durationMinutes = minutes;
      _selectedStartMinutes.clear();
      _error = null;
    });
  }

  void _toggleStart(int minutes) {
    setState(() {
      if (!_selectedStartMinutes.add(minutes)) {
        _selectedStartMinutes.remove(minutes);
      }
      _error = null;
    });
  }

  List<_SlotRange> _ranges() {
    final now = DateTime.now().toUtc();
    final ranges = <_SlotRange>[];
    for (final date in _selectedDates) {
      for (final minute in _selectedStartMinutes) {
        final start = koreaComponentsToUtc(
          date,
          hour: minute ~/ 60,
          minute: minute % 60,
        );
        final end = start.add(Duration(minutes: _durationMinutes));
        if (start.isAfter(now)) ranges.add(_SlotRange(start, end));
      }
    }
    ranges.sort((a, b) => a.startAt.compareTo(b.startAt));
    return ranges;
  }

  void _submit() {
    if (_selectedDates.isEmpty) {
      setState(() => _error = '가능한 날짜를 한 개 이상 선택해 주세요.');
      return;
    }
    if (_selectedStartMinutes.isEmpty) {
      setState(() => _error = '가능한 시작 시간을 한 개 이상 선택해 주세요.');
      return;
    }
    final ranges = _ranges();
    if (ranges.isEmpty) {
      setState(() => _error = '오늘의 지난 시간이 아닌 일정을 선택해 주세요.');
      return;
    }
    if (ranges.length > 100) {
      setState(() => _error = '한 번에 최대 100개까지 등록할 수 있습니다. 날짜나 시간을 조금 줄여 주세요.');
      return;
    }
    Navigator.pop(context, ranges);
  }

  @override
  Widget build(BuildContext context) {
    final ranges = _ranges();
    final rawCount = _selectedDates.length * _selectedStartMinutes.length;
    final skipped = rawCount - ranges.length;
    return Scaffold(
      appBar: AppBar(title: const Text('가능 날짜 · 시간 선택')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  const _StepTitle(
                    number: '1',
                    title: '가능한 날짜를 모두 선택해 주세요',
                    description: '선택한 날짜에는 같은 시간대가 한꺼번에 등록됩니다.',
                  ),
                  const SizedBox(height: 12),
                  _calendarCard(),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _selectVisibleMonth(weekdaysOnly: false),
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('이 달 전체'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _selectVisibleMonth(weekdaysOnly: true),
                        icon: const Icon(Icons.work_outline_rounded),
                        label: const Text('이 달 평일'),
                      ),
                      TextButton(
                        onPressed: _selectedDates.isEmpty
                            ? null
                            : () => setState(() {
                                  _selectedDates.clear();
                                  _error = null;
                                }),
                        child: const Text('날짜 초기화'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_selectedDates.length}일 선택',
                    style: const TextStyle(
                      color: Color(0xFFC6FF00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _StepTitle(
                    number: '2',
                    title: '수업 시간을 선택해 주세요',
                    description: '수업 길이를 바꾸면 시작 시간을 다시 선택합니다.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final duration in const [30, 60, 90, 120])
                        ChoiceChip(
                          key: ValueKey('availability-duration-$duration'),
                          selected: _durationMinutes == duration,
                          showCheckmark: false,
                          selectedColor: const Color(0xFFC6FF00),
                          backgroundColor: const Color(0xFF222936),
                          side: BorderSide(
                            color: _durationMinutes == duration
                                ? const Color(0xFFC6FF00)
                                : const Color(0xFF475569),
                          ),
                          labelStyle: TextStyle(
                            color: _durationMinutes == duration
                                ? const Color(0xFF0D0F12)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          label: Text('$duration분'),
                          onSelected: (_) => _setDuration(duration),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const _StepTitle(
                    number: '3',
                    title: '가능한 시작 시간을 모두 눌러 주세요',
                    description: '오전 6시부터 자정 전까지 버튼으로 선택할 수 있습니다.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      for (final minute in _startMinutes)
                        ChoiceChip(
                          key: ValueKey('availability-time-$minute'),
                          selected: _selectedStartMinutes.contains(minute),
                          showCheckmark: false,
                          selectedColor: const Color(0xFF38BDF8),
                          backgroundColor: const Color(0xFF222936),
                          side: BorderSide(
                            color: _selectedStartMinutes.contains(minute)
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF64748B),
                          ),
                          labelStyle: TextStyle(
                            color: _selectedStartMinutes.contains(minute)
                                ? const Color(0xFF07121D)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          avatar: _selectedStartMinutes.contains(minute)
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Color(0xFF07121D),
                                )
                              : null,
                          label: Text(_clock(minute)),
                          onSelected: (_) => _toggleStart(minute),
                        ),
                    ],
                  ),
                  if (skipped > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '오늘 이미 지난 시간 $skipped개는 등록에서 자동으로 제외됩니다.',
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: .45),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF141620),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('save-bulk-availability'),
                  onPressed: _submit,
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text('선택한 가능 시간 ${ranges.length}개 등록'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarCard() {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leading = first.weekday - 1;
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final earliestMonth = DateTime(_today.year, _today.month);
    final latestMonth = DateTime(_lastDate.year, _lastDate.month);
    return Card(
      color: const Color(0xFF171B24),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '이전 달',
                  onPressed: _visibleMonth.isAfter(earliestMonth)
                      ? () => _changeMonth(-1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '다음 달',
                  onPressed: _visibleMonth.isBefore(latestMonth)
                      ? () => _changeMonth(1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var index = 0; index < weekdays.length; index += 1)
                  Expanded(
                    child: Text(
                      weekdays[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: index == 5
                            ? const Color(0xFF38BDF8)
                            : index == 6
                                ? Colors.redAccent
                                : Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final day = index - leading + 1;
                if (day < 1 || day > days) return const SizedBox.shrink();
                final date = DateTime(first.year, first.month, day);
                final enabled = _selectable(date);
                final selected = _selected(date);
                final today = _sameDay(date, _today);
                final dateKey =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                return Semantics(
                  selected: selected,
                  button: true,
                  label: '$dateKey ${selected ? '선택됨' : '선택 안 됨'}',
                  child: InkWell(
                    key: ValueKey('availability-day-$dateKey'),
                    onTap: enabled ? () => _toggleDate(date) : null,
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFC6FF00) : null,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFC6FF00)
                              : today
                                  ? const Color(0xFF38BDF8)
                                  : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: !enabled
                              ? Colors.white24
                              : selected
                                  ? const Color(0xFF0D0F12)
                                  : date.weekday == DateTime.sunday
                                      ? Colors.redAccent
                                      : date.weekday == DateTime.saturday
                                          ? const Color(0xFF38BDF8)
                                          : Colors.white,
                          fontWeight:
                              selected || today ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
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
              color: Color(0xFFC6FF00),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF0D0F12),
                fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w700,
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
    final start = widget.slot == null ? now : toKoreaTime(widget.slot!.startAt);
    final end = widget.slot == null
        ? start.add(const Duration(hours: 1))
        : toKoreaTime(widget.slot!.endAt);
    _date = DateTime(start.year, start.month, start.day);
    _start = widget.slot == null
        ? TimeOfDay(hour: (start.hour + 1).clamp(0, 23), minute: 0)
        : TimeOfDay(hour: start.hour, minute: start.minute);
    _end = widget.slot == null
        ? TimeOfDay(hour: (start.hour + 2).clamp(0, 23), minute: 0)
        : TimeOfDay(hour: end.hour, minute: end.minute);
  }

  Future<void> _pickDate() async {
    final todayKorea = koreaNow();
    final today = DateTime(todayKorea.year, todayKorea.month, todayKorea.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
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
    final endAt = koreaComponentsToUtc(
      _date,
      hour: _end.hour,
      minute: _end.minute,
    );
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
        backgroundColor: const Color(0xFF171B24),
        surfaceTintColor: const Color(0xFF171B24),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        title: Text(widget.slot == null ? '가능 시간 추가' : '가능 시간 수정'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('모든 날짜와 시간은 한국 시간(KST) 기준입니다.'),
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
    primary: Color(0xFFC6FF00),
    onPrimary: Color(0xFF0D0F12),
    surface: Color(0xFF171B24),
    onSurface: Colors.white,
    outline: Color(0xFF64748B),
  );
  return base.copyWith(
    colorScheme: colors,
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF171B24),
      surfaceTintColor: Color(0xFF171B24),
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: Color(0xFF171B24),
      hourMinuteColor: Color(0xFF263244),
      hourMinuteTextColor: Colors.white,
      dialBackgroundColor: Color(0xFF263244),
      dialHandColor: Color(0xFFC6FF00),
      dialTextColor: Colors.white,
      entryModeIconColor: Color(0xFF38BDF8),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: Color(0xFF171B24),
      surfaceTintColor: Color(0xFF171B24),
      headerBackgroundColor: Color(0xFF263244),
      headerForegroundColor: Colors.white,
      weekdayStyle: TextStyle(color: Colors.white70),
      dayForegroundColor: WidgetStatePropertyAll(Colors.white),
      yearForegroundColor: WidgetStatePropertyAll(Colors.white),
    ),
  );
}
