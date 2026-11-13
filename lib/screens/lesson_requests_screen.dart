import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lesson_slot.dart';
import '../services/coach_availability_service.dart';
import '../services/matching_service.dart';
import '../services/payment_service.dart';
import '../utils/korea_time.dart';
import 'payment_checkout_screen.dart';
import 'payment_history_screen.dart';
import 'chat_room_screen.dart';
import 'lesson_badges_screen.dart';
import 'lesson_feedback_videos_screen.dart';
import 'lesson_slot_picker_screen.dart';

class LessonRequestsScreen extends StatefulWidget {
  final MatchingService? service;
  final PaymentService? paymentService;
  final CoachAvailabilityService? availabilityService;

  const LessonRequestsScreen({
    super.key,
    this.service,
    this.paymentService,
    this.availabilityService,
  });

  @override
  State<LessonRequestsScreen> createState() => _LessonRequestsScreenState();
}

class _LessonRequestsScreenState extends State<LessonRequestsScreen> {
  late final MatchingService _service;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _lessons;
  final Set<String> _busyRequests = {};
  late final _payments = widget.paymentService ?? PaymentService();
  CoachAvailabilityService? _availabilityInstance;
  CoachAvailabilityService get _availability => _availabilityInstance ??=
      widget.availabilityService ?? CoachAvailabilityService();

  Future<void> _reschedule(
    String lessonId,
    String coachUid,
    String coachName,
  ) async {
    final slot = await Navigator.push<LessonSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => LessonSlotPickerScreen(
          coachUid: coachUid,
          coachName: coachName,
          title: '레슨 날짜 변경',
        ),
      ),
    );
    if (slot == null || !mounted) return;
    await _runAction(
      lessonId,
      () => _availability.rescheduleLesson(lessonId, slot.id),
      successMessage: '레슨 날짜를 변경했습니다. 상대방의 내 레슨에도 즉시 표시됩니다.',
    );
  }

  void _showScheduleHistory(String lessonId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ScheduleHistorySheet(
        lessonId: lessonId,
        service: _availability,
      ),
    );
  }

  Future<void> _acceptPaid(String id) async {
    final amount = TextEditingController();
    final value = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1A1C29),
              titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              title: const Text('레슨 금액 확정'),
              content: TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '레슨 금액 (원)', hintText: '코치가 정한 금액을 입력하세요.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기')),
                FilledButton(
                    onPressed: () {
                      final price = int.tryParse(amount.text);
                      if (price != null && price >= 100 && price <= 10000000) {
                        Navigator.pop(context, price);
                      }
                    },
                    child: const Text('금액 확정 및 수락'))
              ],
            ));
    amount.dispose();
    if (value != null && mounted) {
      await _runAction(id, () => _payments.accept(id, value),
          successMessage: '레슨 금액을 확정했습니다. 수강생 결제 후 예약이 확정됩니다.');
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MatchingService();
    _lessons = _service.lessons();
  }

  Future<void> _runAction(
    String requestId,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busyRequests.contains(requestId)) return;
    setState(() => _busyRequests.add(requestId));
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        StateError() => error.message.toString(),
        ArgumentError() => error.message.toString(),
        _ => paymentError(error),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _busyRequests.remove(requestId));
    }
  }

  Future<void> _completeLesson(
      String requestId, String studentName, String signatureMove,
      {bool paidLesson = false}) {
    return _runAction(requestId, () async {
      final currentSignature =
          await _service.currentSignatureMove(fallback: signatureMove);
      if (!mounted) return;
      if (currentSignature.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('마이페이지의 시그니처 뱃지 관리에서 뱃지를 먼저 등록해 주세요.'),
        ));
        return;
      }
      final review = await showDialog<_LessonReview>(
        context: context,
        builder: (context) => _LessonReviewDialog(
          studentName: studentName,
          signatureMove: currentSignature,
        ),
      );
      if (review == null || !mounted) return;
      if (paidLesson) {
        await _payments.complete(
            requestId, review.score, review.feedback, review.signatureMove);
      } else {
        await _service.completeLesson(
          requestId: requestId,
          reviewScore: review.score,
          feedback: review.feedback,
          signatureMove: review.signatureMove,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('출석을 인증하고 ${review.signatureMove} 뱃지를 지급했습니다.')),
      );
    });
  }

  String _statusLabel(String status) => switch (status) {
        'pending' => '수락 대기',
        'accepted' => '진행 중',
        'completed' => '완료',
        'confirmed' => '예약 확정',
        'rejected' => '거절됨',
        'cancelled' => '취소됨',
        _ => '상태 확인 필요',
      };

  int _createdAt(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 레슨'),
        actions: [
          IconButton(
            tooltip: '내 출석 뱃지',
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LessonBadgesScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _lessons,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('레슨 내역을 불러오지 못했습니다.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _lessons = _service.lessons();
                    }),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lessons = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final byDate =
                  _createdAt(b.data()).compareTo(_createdAt(a.data()));
              return byDate != 0 ? byDate : a.id.compareTo(b.id);
            });
          if (lessons.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '아직 레슨 내역이 없습니다.\n홈에서 코치를 선택해 레슨을 신청해 보세요.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lessons.length,
            itemBuilder: (context, index) => _buildLesson(lessons[index]),
          );
        },
      ),
    );
  }

  Widget _buildLesson(QueryDocumentSnapshot<Map<String, dynamic>> lesson) {
    final data = lesson.data();
    final studentUid = data['studentUid'] as String? ?? '';
    final instructorUid = data['instructorUid'] as String? ?? '';
    final studentName = data['studentName'] as String? ?? '수강생';
    final instructorName = data['instructorName'] as String? ?? '코치';
    final isInstructor =
        instructorUid.isNotEmpty && instructorUid == _service.currentUid;
    final isStudent =
        studentUid.isNotEmpty && studentUid == _service.currentUid;
    final targetName = isInstructor ? studentName : instructorName;
    final status = data['status'] as String? ?? '';
    final busy = _busyRequests.contains(lesson.id);
    final createdAt = data['createdAt'];
    final reviewScore = data['reviewScore'] as num?;
    final feedback = data['reviewFeedback'] as String? ?? '';
    final signatureMove = data['signatureMove'] as String? ?? '';
    final attendanceBadge = data['attendanceBadge'];
    final scheduledStartAt = data['scheduledStartAt'];
    final scheduledEndAt = data['scheduledEndAt'];
    final scheduleRevision = (data['scheduleRevision'] as num?)?.toInt() ?? 0;
    final canReschedule = (isInstructor || isStudent) &&
        const ['pending', 'accepted', 'confirmed'].contains(status) &&
        instructorUid.isNotEmpty;
    final canChat = (isInstructor || isStudent) &&
        const ['accepted', 'confirmed', 'completed'].contains(status) &&
        studentUid.isNotEmpty &&
        instructorUid.isNotEmpty &&
        studentUid != instructorUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$targetName ${isInstructor ? '수강생' : '코치'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                    label: Text(status == 'accepted' && data['price'] is num
                        ? '결제 대기'
                        : _statusLabel(status))),
              ],
            ),
            if (createdAt is Timestamp)
              Text(
                '신청일 ${formatKoreaDateTime(createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF102238),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF28527A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.event_rounded,
                          color: Color(0xFF7DD3FC), size: 20),
                      SizedBox(width: 8),
                      Text('레슨 일정',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatKoreaTimeRange(
                      scheduledStartAt,
                      scheduledEndAt,
                      fallback: '일정 미정 (기존 신청)',
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  if (scheduleRevision > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '일정이 $scheduleRevision회 변경되었습니다. 최신 확정 일정을 표시합니다.',
                      style: const TextStyle(
                          color: Color(0xFFBAE6FD), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (data['price'] is num)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('레슨 금액 ${won(data['price'])}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold))),
            if (status == 'completed') ...[
              const SizedBox(height: 12),
              Text(
                reviewScore == null
                    ? '완료된 레슨입니다.'
                    : '수강생 평가: ${reviewScore.toStringAsFixed(1)} / 5',
              ),
              if (feedback.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(feedback),
              ],
              if (attendanceBadge is Map &&
                  attendanceBadge['signatureMove'] is String) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182721),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF426439)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFC6FF00), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${attendanceBadge['signatureMove']}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isInstructor
                                  ? '참여 확인 완료 · 출석 뱃지 지급'
                                  : '코치 참여 확인 완료 · 출석 뱃지 획득',
                              style: const TextStyle(
                                  color: Color(0xFFC6FF00), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (status == 'accepted' && isStudent) ...[
              const SizedBox(height: 12),
              Text(
                signatureMove.trim().isEmpty
                    ? '레슨 후 코치가 참여를 확인하면 시그니처 뱃지를 받아요.'
                    : '레슨 참여 인증 후 받을 뱃지: $signatureMove',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'pending' && isInstructor) ...[
                  if (data['paymentRequired'] == true)
                    FilledButton(
                        onPressed: busy ? null : () => _acceptPaid(lesson.id),
                        child: const Text('유료 레슨 수락')),
                  if (data['paymentRequired'] != true)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _runAction(
                                lesson.id,
                                () => _service.acceptLesson(lesson.id),
                                successMessage: '레슨 신청을 수락했습니다.',
                              ),
                      child: const Text('수락'),
                    ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _runAction(
                              lesson.id,
                              () => _service.rejectLesson(lesson.id),
                              successMessage: '레슨 신청을 거절했습니다.',
                            ),
                    child: const Text('거절'),
                  ),
                ],
                if (status == 'pending' && isStudent)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _runAction(
                              lesson.id,
                              () => _service.cancelLesson(lesson.id),
                              successMessage: '레슨 신청을 취소했습니다.',
                            ),
                    child: const Text('신청 취소'),
                  ),
                if (status == 'accepted' && isStudent && data['price'] is num)
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PaymentCheckoutScreen(
                                      lessonId: lesson.id,
                                      instructorName: instructorName,
                                      service: _payments))),
                      child: const Text('결제하기')),
                if (status == 'accepted' &&
                    data['price'] is num &&
                    (isStudent || isInstructor))
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _runAction(lesson.id,
                              () => _payments.cancelUnpaid(lesson.id)),
                      child: const Text('결제 전 취소')),
                if (data['paymentId'] is String)
                  TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PaymentHistoryScreen(
                                      coachMode: isInstructor,
                                      service: _payments))),
                      child: const Text('결제 / 정산 내역')),
                if (canReschedule)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _reschedule(
                              lesson.id,
                              instructorUid,
                              instructorName,
                            ),
                    icon: const Icon(Icons.edit_calendar_rounded),
                    label: Text(scheduledStartAt == null ? '날짜 지정' : '날짜 변경'),
                  ),
                if (scheduleRevision > 0)
                  TextButton.icon(
                    onPressed: () => _showScheduleHistory(lesson.id),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('변경 내역'),
                  ),
                if ((status == 'confirmed' ||
                        (status == 'accepted' &&
                            data['price'] == null &&
                            data['paymentRequired'] != true)) &&
                    isInstructor)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _completeLesson(
                            lesson.id, studentName, signatureMove,
                            paidLesson: status == 'confirmed'),
                    child: const Text('레슨 완료 및 평가'),
                  ),
                if (canChat)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            final ids = [studentUid, instructorUid]..sort();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatRoomScreen(
                                  roomId: ids.join('_'),
                                  targetName: targetName,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('채팅'),
                  ),
                if ((isInstructor || isStudent) &&
                    const ['accepted', 'confirmed', 'completed']
                        .contains(status))
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LessonFeedbackVideosScreen(
                                  lessonId: lesson.id,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('피드백 영상'),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleHistorySheet extends StatelessWidget {
  const _ScheduleHistorySheet({
    required this.lessonId,
    required this.service,
  });

  final String lessonId;
  final CoachAvailabilityService service;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '레슨 일정 변경 내역',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<LessonScheduleChange>>(
                  stream: service.scheduleHistory(lessonId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Text(availabilityError(snapshot.error!)));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.isEmpty) {
                      return const Center(child: Text('기록된 일정 변경이 없습니다.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: snapshot.data!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final change = snapshot.data![index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '변경 후 · ${formatKoreaTimeRange(change.newStartAt, change.newEndAt)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  change.previousStartAt == null ||
                                          change.previousEndAt == null
                                      ? '변경 전 · 일정 미정 (기존 신청)'
                                      : '변경 전 · ${formatKoreaTimeRange(change.previousStartAt, change.previousEndAt)}',
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formatKoreaDateTime(
                                    change.changedAt,
                                    fallback: '변경 시각 확인 중',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${change.changedByName}님이 변경',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _LessonReview {
  final double score;
  final String feedback;
  final String signatureMove;

  const _LessonReview(this.score, this.feedback, this.signatureMove);
}

class _LessonReviewDialog extends StatefulWidget {
  final String studentName;
  final String signatureMove;

  const _LessonReviewDialog({
    required this.studentName,
    required this.signatureMove,
  });

  @override
  State<_LessonReviewDialog> createState() => _LessonReviewDialogState();
}

class _LessonReviewDialogState extends State<_LessonReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackController = TextEditingController();
  late final TextEditingController _signatureController;
  double? _score;

  @override
  void initState() {
    super.initState();
    _signatureController = TextEditingController(text: widget.signatureMove);
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
          color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold),
      title: const Text('레슨 완료 및 평가'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: DefaultTextStyle(
              style: const TextStyle(color: Color(0xFF1E293B), height: 1.45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.studentName} 수강생의 레슨 참여를 확인하고 평가해 주세요.\n출석 인증 시 시그니처 뱃지가 지급되고 EXP가 반영됩니다.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('lesson-signature-move'),
                    controller: _signatureController,
                    readOnly: true,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: _fieldDecoration(
                      label: '지급할 시그니처 뱃지',
                      hint: '마이페이지에서 시그니처 뱃지를 먼저 선택해 주세요.',
                      helper: '뱃지 변경은 마이페이지의 시그니처 뱃지 관리에서 할 수 있습니다.',
                      suffixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '시그니처 기술을 입력해 주세요.';
                      }
                      if (value.trim().length > 40) {
                        return '시그니처 기술은 40자 이내로 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<double>(
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: _fieldDecoration(label: '수강생 평가 점수'),
                    hint: const Text('1~5점 선택',
                        style: TextStyle(color: Color(0xFF64748B))),
                    items: List.generate(5, (index) {
                      final score = index + 1;
                      return DropdownMenuItem(
                        value: score.toDouble(),
                        child: Text('$score점'),
                      );
                    }),
                    onChanged: (value) => _score = value,
                    validator: (value) =>
                        value == null ? '평가 점수를 선택해 주세요.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('lesson-feedback'),
                    controller: _feedbackController,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: _fieldDecoration(
                      label: '피드백 (선택)',
                      hint: '잘한 점과 연습할 점을 남겨 주세요.',
                      alignLabelWithHint: true,
                    ),
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 1000,
                  ),
                  FormField<bool>(
                    initialValue: false,
                    validator: (value) =>
                        value == true ? null : '실제 레슨 참여 여부를 확인해 주세요.',
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          key: const ValueKey('lesson-attendance-confirmation'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFF0284C7),
                          title: const Text(
                            '실제 레슨 참여를 확인했습니다.',
                            style: TextStyle(color: Color(0xFF0F172A)),
                          ),
                          value: field.value ?? false,
                          onChanged: field.didChange,
                        ),
                        if (field.hasError)
                          Text(field.errorText!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기', style: TextStyle(color: Color(0xFF475569))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _LessonReview(_score!, _feedbackController.text.trim(),
                  _signatureController.text.trim()),
            );
          },
          child: const Text('평가하고 완료'),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
    bool alignLabelWithHint = false,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        alignLabelWithHint: alignLabelWithHint,
        suffixIcon: suffixIcon,
        labelStyle: const TextStyle(color: Color(0xFF475569)),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        helperStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2),
        ),
      );
}
