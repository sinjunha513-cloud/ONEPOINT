import 'package:flutter/material.dart';

import '../models/lesson_slot.dart';
import '../services/coach_availability_service.dart';
import '../utils/korea_time.dart';

class LessonSlotPickerScreen extends StatefulWidget {
  const LessonSlotPickerScreen({
    super.key,
    required this.coachUid,
    required this.coachName,
    this.service,
    this.title = '레슨 날짜 선택',
  });

  final String coachUid;
  final String coachName;
  final CoachAvailabilityService? service;
  final String title;

  @override
  State<LessonSlotPickerScreen> createState() => _LessonSlotPickerScreenState();
}

class _LessonSlotPickerScreenState extends State<LessonSlotPickerScreen> {
  late final CoachAvailabilityService _service =
      widget.service ?? CoachAvailabilityService();
  DateTime? _selectedDate;
  String? _selectedSlotId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: StreamBuilder<List<LessonSlot>>(
          stream: _service.slotsForCoach(widget.coachUid, availableOnly: true),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    availabilityError(snapshot.error!),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final slots = snapshot.data!;
            if (slots.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_busy_rounded, size: 48),
                      const SizedBox(height: 16),
                      Text('${widget.coachName} 코치가 등록한 신청 가능 시간이 없습니다.'),
                      const SizedBox(height: 8),
                      const Text(
                        '코치가 가능 시간을 등록한 뒤 다시 확인해 주세요.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            final first = koreaDateOnly(slots.first.startAt);
            final selectedDate = _selectedDate ?? first;
            final daySlots = slots
                .where((slot) => sameKoreaDate(slot.startAt, selectedDate))
                .toList(growable: false);
            LessonSlot? selected;
            for (final slot in slots) {
              if (slot.id == _selectedSlotId) selected = slot;
            }
            final last = koreaDateOnly(slots.last.startAt);
            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              '${widget.coachName} 코치의 신청 가능 시간만 표시됩니다. 시간은 한국 시간(KST) 기준입니다.',
                            ),
                          ),
                        ),
                        CalendarDatePicker(
                          key: ValueKey(
                              '${first.toIso8601String()}-${last.toIso8601String()}'),
                          initialDate: selectedDate,
                          firstDate: first,
                          lastDate: last,
                          selectableDayPredicate: (date) => slots.any(
                            (slot) => sameKoreaDate(slot.startAt, date),
                          ),
                          onDateChanged: (date) => setState(() {
                            _selectedDate = date;
                            _selectedSlotId = null;
                          }),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${formatKoreaDate(selectedDate)} 가능 시간',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (daySlots.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('이 날짜에는 신청 가능한 시간이 없습니다.'),
                          )
                        else
                          for (final slot in daySlots)
                            Card(
                              color: _selectedSlotId == slot.id
                                  ? const Color(0xFF173A52)
                                  : null,
                              child: ListTile(
                                onTap: () =>
                                    setState(() => _selectedSlotId = slot.id),
                                leading: Icon(
                                  _selectedSlotId == slot.id
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: const Color(0xFF38BDF8),
                                ),
                                title: Text(
                                  formatKoreaClockRange(
                                    slot.startAt,
                                    slot.endAt,
                                  ),
                                ),
                                subtitle: const Text('신청 가능'),
                              ),
                            ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected == null
                            ? null
                            : () => Navigator.pop(context, selected),
                        icon: const Icon(Icons.event_available_rounded),
                        label: Text(widget.title == '레슨 날짜 선택'
                            ? '이 시간으로 신청'
                            : '이 시간으로 변경'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}
