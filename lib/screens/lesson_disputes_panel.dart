import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/matching_service.dart';
import '../utils/korea_time.dart';
import '../widgets/lesson_workflow_panel.dart';
import '../services/coupon_service.dart';

class LessonDisputesPanel extends StatefulWidget {
  const LessonDisputesPanel(
      {super.key, required this.firestore, required this.auth});
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  @override
  State<LessonDisputesPanel> createState() => _LessonDisputesPanelState();
}

class _LessonDisputesPanelState extends State<LessonDisputesPanel> {
  late final _service =
      MatchingService(firestore: widget.firestore, auth: widget.auth);
  late final _items = widget.firestore
      .collection('lesson_requests')
      .where('completionReview.status', isEqualTo: 'disputed')
      .snapshots();
  final _busy = <String>{};
  Future<void> _resolve(
      String id, String decision, String label, int revision) async {
    final note = await askLessonReason(context, '$label · 처리 사유');
    if (note == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await _service.resolveDispute(id, decision, note, revision: revision);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(couponError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('이의 제기를 불러오지 못했습니다.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('검토 중인 레슨 이의 제기가 없습니다.'));
            }
            return ListView(
                padding: const EdgeInsets.all(16),
                children: [for (final doc in snapshot.data!.docs) _card(doc)]);
          });
  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data(),
        review = Map<String, dynamic>.from(d['completionReview'] as Map);
    final busy = _busy.contains(doc.id);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${d['studentName'] ?? '수강생'} · ${d['instructorName'] ?? '코치'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(formatKoreaTimeRange(
                  d['scheduledStartAt'], d['scheduledEndAt'])),
              const SizedBox(height: 8),
              Text('이의 사유: ${review['disputeReason'] ?? ''}'),
              if (review['feedback'] is String)
                Text('코치 의견: ${review['feedback']}'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                if (review['attendanceBadge'] is Map)
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => _resolve(doc.id, 'confirm', '완료 인정',
                              (review['revision'] as num).toInt()),
                      child: const Text('완료 인정')),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _resolve(doc.id, 'reopen', '다시 협의',
                            (review['revision'] as num).toInt()),
                    child: const Text('다시 협의')),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _resolve(doc.id, 'cancel', '수업 취소',
                            (review['revision'] as num).toInt()),
                    child: const Text('수업 취소')),
              ]),
            ])));
  }
}
