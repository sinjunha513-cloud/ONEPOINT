import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';
import '../services/matching_service.dart';
import '../utils/korea_time.dart';

Future<String?> askLessonReason(BuildContext context, String title) =>
    showDialog<String>(
        context: context, builder: (_) => _LessonReasonDialog(title: title));

class _LessonReasonDialog extends StatefulWidget {
  const _LessonReasonDialog({required this.title});
  final String title;
  @override
  State<_LessonReasonDialog> createState() => _LessonReasonDialogState();
}

class _LessonReasonDialogState extends State<_LessonReasonDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: TextField(
              controller: text,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '사유 (필수)')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기')),
            FilledButton(
                onPressed: () {
                  if (text.text.trim().isNotEmpty) {
                    Navigator.pop(context, text.text.trim());
                  }
                },
                child: const Text('제출'))
          ]);
}

class LessonWorkflowPanel extends StatelessWidget {
  const LessonWorkflowPanel(
      {super.key,
      required this.lessonId,
      required this.data,
      required this.service,
      required this.busy,
      required this.run});
  final String lessonId;
  final Map<String, dynamic> data;
  final MatchingService service;
  final bool busy;
  final Future<void> Function(Future<void> Function(), String) run;
  @override
  Widget build(BuildContext context) {
    final proposal = data['scheduleProposal'];
    final review = data['completionReview'];
    final student = data['studentUid'] == service.currentUid;
    final deadline = data['expiresAt'];
    final end = timestampDate(data['scheduledEndAt']);
    final ended = end != null && !end.isAfter(DateTime.now().toUtc());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (data['status'] == 'pending' && deadline != null)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                '응답 기한: ${formatKoreaDateTime(deadline)}\n24시간 또는 수업 시작 시각까지 응답이 없으면 자동 만료돼요.',
                style: const TextStyle(
                    color: OnepointDesign.muted, fontSize: 12))),
      if (data['cancellationReason'] is String &&
          data['cancellationReason'] != '')
        Text('취소 사유: ${data['cancellationReason']}'),
      if (proposal is Map &&
          proposal['status'] == 'pending' &&
          const ['pending', 'accepted'].contains(data['status']))
        _box([
          const Text('날짜 변경 승인 대기',
              style: TextStyle(
                  color: OnepointDesign.lime, fontWeight: FontWeight.w600)),
          Text(formatKoreaTimeRange(proposal['startAt'], proposal['endAt'])),
          Text('응답 기한: ${formatKoreaDateTime(proposal['expiresAt'])}'),
          const Text('승인 전에는 기존 일정이 유지됩니다.',
              style: TextStyle(color: OnepointDesign.muted, fontSize: 12)),
          Wrap(
              spacing: 8,
              children: proposal['requestedBy'] == service.currentUid
                  ? [
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => service.respondSchedule(
                                      lessonId, 'withdraw',
                                      revision: (proposal['revision'] as num)
                                          .toInt()),
                                  '변경 요청을 철회했습니다.'),
                          child: const Text('요청 철회')),
                    ]
                  : [
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => service.respondSchedule(
                                      lessonId, 'approve',
                                      revision: (proposal['revision'] as num)
                                          .toInt()),
                                  '변경 일정을 승인했습니다.'),
                          child: const Text('변경 승인')),
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => service.respondSchedule(
                                      lessonId, 'reject',
                                      revision: (proposal['revision'] as num)
                                          .toInt()),
                                  '변경 요청을 거절했습니다.'),
                          child: const Text('변경 거절')),
                    ]),
        ]),
      if (review is Map &&
          review['status'] == 'pending' &&
          data['status'] == 'accepted')
        _box([
          Text(student ? '수업 참여를 확인해 주세요' : '수강생 참여 확인 대기',
              style: const TextStyle(
                  color: OnepointDesign.lime, fontWeight: FontWeight.w600)),
          const Text('수강생이 확인한 뒤 완료 횟수·뱃지·EXP에 반영됩니다.',
              style: TextStyle(color: OnepointDesign.muted, fontSize: 12)),
          if (student)
            Wrap(spacing: 8, children: [
              FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => service.respondCompletion(lessonId, 'confirm',
                              revision: (review['revision'] as num).toInt()),
                          '참여를 확인하고 레슨을 완료했습니다.'),
                  child: const Text('참여 확인 · 완료')),
              OutlinedButton(
                  onPressed: busy ? null : () => _dispute(context),
                  child: const Text('이의 제기')),
            ]),
        ]),
      if (review is Map && review['status'] == 'disputed')
        _box([
          const Text('완료 이의 제기 · 검토 중',
              style: TextStyle(
                  color: OnepointDesign.blue, fontWeight: FontWeight.w600)),
          Text('${review['disputeReason'] ?? ''}'),
          const Text('관리자 검토를 위해 접수됐습니다. 처리 결과에 따라 완료 확인을 다시 진행할 수 있어요.',
              style: TextStyle(color: OnepointDesign.muted, fontSize: 12)),
        ]),
      if (review is Map && review['resolutionReason'] is String)
        Text('관리자 처리 사유: ${review['resolutionReason']}'),
      if (student &&
          data['status'] == 'accepted' &&
          ended &&
          (review is! Map ||
              !['pending', 'disputed'].contains(review['status'])))
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: busy ? null : () => _dispute(context),
                child: const Text('수업 미진행 · 완료 이의 제기'))),
    ]);
  }

  Future<void> _dispute(BuildContext context) async {
    final reason = await askLessonReason(context, '레슨 완료 이의 제기');
    if (reason != null) {
      await run(
          () => service.respondCompletion(lessonId, 'dispute',
              reason: reason,
              revision:
                  ((data['completionReview'] as Map?)?['revision'] as num?)
                          ?.toInt() ??
                      0),
          '이의 제기를 접수했습니다.');
    }
  }

  Widget _box(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: child)
      ]));
}
