import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/community_service.dart';
import '../widgets/lesson_workflow_panel.dart';
import 'admin_member_detail_screen.dart';
import '../widget/video_item_widget.dart';

class ReportsManagementPanel extends StatefulWidget {
  const ReportsManagementPanel(
      {super.key, required this.firestore, required this.auth, this.service});
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final CommunityService? service;
  @override
  State<ReportsManagementPanel> createState() => _ReportsManagementPanelState();
}

class _ReportsManagementPanelState extends State<ReportsManagementPanel> {
  late final _service = widget.service ??
      CommunityService(firestore: widget.firestore, auth: widget.auth);
  int _limit = 50;
  final _busy = <String>{};
  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream => widget.firestore
      .collection('reports')
      .where('status', whereIn: ['pending', 'PENDING'])
      .limit(_limit)
      .snapshots();
  Future<void> _resolve(String id, String action) async {
    final reason = await askLessonReason(context, '신고 처리 사유');
    if (reason == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await _service.resolveReport(id, action, reason);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(communityError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, s) {
            if (s.hasError) {
              return const Center(child: Text('신고 목록을 불러오지 못했습니다.'));
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.data!.docs.isEmpty) {
              return const Center(child: Text('검토할 신고가 없습니다.'));
            }
            final docs = s.data!.docs.toList()
              ..sort((a, b) => ((b.data()['createdAt'] ?? b.data()['timestamp'])
                          as Timestamp? ??
                      Timestamp(0, 0))
                  .compareTo((a.data()['createdAt'] ?? a.data()['timestamp'])
                          as Timestamp? ??
                      Timestamp(0, 0)));
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final d in docs) _card(d),
              if (docs.length >= _limit)
                OutlinedButton(
                    onPressed: () => setState(() => _limit += 50),
                    child: const Text('신고 더 보기'))
            ]);
          });
  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data(), target = d['reportedUid'] ?? d['reportedUserId'];
    final busy = _busy.contains(doc.id);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(d['reportedUserName'] as String? ?? '회원',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(d['reason'] as String? ?? ''),
                  const SizedBox(height: 8),
                  Text((d['details'] ?? d['detail'] ?? '').toString()),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(
                        onPressed:
                            busy ? null : () => _resolve(doc.id, 'dismiss'),
                        child: const Text('조치 없이 종결')),
                    FilledButton(
                        onPressed: busy ? null : () => _resolve(doc.id, 'warn'),
                        child: const Text('경고 안내')),
                    if (d['targetType'] == 'feed')
                      OutlinedButton(
                          onPressed:
                              busy ? null : () => _resolve(doc.id, 'hide'),
                          child: const Text('영상 숨기기')),
                    if (d['targetType'] == 'feed')
                      TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                  child: SizedBox(
                                      width: 360,
                                      height: 540,
                                      child: VideoItemWidget(
                                          videoUrl: '',
                                          videoId: d['targetId'] as String,
                                          autoplay: false)))),
                          child: const Text('영상 확인')),
                    if (target is String)
                      TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AdminMemberDetailScreen(
                                      uid: target,
                                      firestore: widget.firestore))),
                          child: const Text('회원·제재 내역')),
                  ])
                ])));
  }
}
