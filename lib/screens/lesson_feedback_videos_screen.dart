import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/video_upload_service.dart';
import '../utils/korea_time.dart';
import '../widget/video_item_widget.dart';
import 'video_upload_screen.dart';

class LessonFeedbackVideosScreen extends StatefulWidget {
  const LessonFeedbackVideosScreen(
      {super.key,
      required this.lessonId,
      this.firestore,
      this.auth,
      this.videoService});

  final String lessonId;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final VideoUploadService? videoService;

  @override
  State<LessonFeedbackVideosScreen> createState() =>
      _LessonFeedbackVideosScreenState();
}

class _LessonFeedbackVideosScreenState
    extends State<LessonFeedbackVideosScreen> {
  int _page = 0;
  VideoUploadService? _videoService;
  final Set<String> _deleting = <String>{};
  final Set<String> _sharing = <String>{};
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  late final _auth = widget.auth ?? FirebaseAuth.instance;

  String? get _currentUid => _auth.currentUser?.uid;
  VideoUploadService get _videos => _videoService ??=
      widget.videoService ?? VideoUploadService(firestore: _db, auth: _auth);

  Future<void> _setPublic(String id, bool value) async {
    if (_sharing.contains(id)) return;
    if (value) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('공개 피드에 게시'),
                  content:
                      const Text('이 영상과 설명을 로그인한 모든 이용자가 공개 피드에서 볼 수 있습니다.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('전체 공개로 게시'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    setState(() => _sharing.add(id));
    try {
      await _videos.setFeedbackPublic(
          lessonId: widget.lessonId, videoId: id, isPublic: value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(value ? '공개 피드에 게시했습니다.' : '공개 피드 게시를 중지했습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is FirebaseException &&
                    RegExp(r'[가-힣]').hasMatch(e.message ?? '')
                ? e.message!
                : '공개 범위를 저장하지 못했습니다. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _sharing.remove(id));
    }
  }

  Future<void> _deleteFeedback(String videoId) async {
    if (_deleting.contains(videoId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B24),
        title: const Text('피드백 영상 삭제'),
        content: const Text('이 영상을 레슨 목록과 공개 피드에서 함께 삭제할까요? 삭제 후 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(videoId));
    try {
      await _videos.deleteLessonFeedback(
        lessonId: widget.lessonId,
        videoId: videoId,
      );
      if (!mounted) return;
      setState(() => _page = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('피드백 영상을 삭제했습니다.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(videoDeleteError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(videoId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('레슨 피드백 영상')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('lesson_requests')
              .doc(widget.lessonId)
              .collection('feedback_videos')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '피드백 영상을 불러오지 못했습니다. 레슨 참여 권한과 연결 상태를 확인해 주세요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final videos = snapshot.data!.docs;
            if (videos.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    '아직 등록된 피드백 영상이 없습니다.\n영상을 등록하면 모든 이용자가 공개 피드에서 볼 수 있어요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return PageView.builder(
              key: ValueKey('feedback-pages-${videos.length}'),
              scrollDirection: Axis.vertical,
              itemCount: videos.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                final data = videos[index].data();
                final videoId = videos[index].id;
                final storagePath = data['storagePath'] as String? ?? '';
                final ownVideo = data['uploaderUid'] == _currentUid;
                final deleting = _deleting.contains(videoId);
                final isPublic = data['visibility'] == 'public';
                final hidden = data['moderationStatus'] == 'hidden';
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoItemWidget(
                      key: ValueKey(videoId),
                      videoUrl: storagePath,
                      videoId: videoId,
                      lessonId: widget.lessonId,
                      autoplay: false,
                      fit: BoxFit.contain,
                      isPlaying: index == _page,
                    ),
                    Positioned(
                        top: 12,
                        left: 12,
                        right: 70,
                        child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                  avatar: Icon(
                                      isPublic
                                          ? Icons.public
                                          : Icons.lock_outline,
                                      size: 16),
                                  label: Text(hidden
                                      ? '공개 피드 숨김'
                                      : isPublic
                                          ? '전체 공개'
                                          : '레슨 참여자만')),
                              if (ownVideo)
                                OutlinedButton(
                                    onPressed: deleting ||
                                            (hidden && !isPublic) ||
                                            _sharing.contains(videoId)
                                        ? null
                                        : () => _setPublic(videoId, !isPublic),
                                    child:
                                        Text(isPublic ? '공개 중지' : '공개 피드에 게시')),
                            ])),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              data['uploaderName'] as String? ?? '레슨 참여자',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if ((data['description'] as String? ?? '')
                                .isNotEmpty)
                              Text(
                                data['description'] as String,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              formatKoreaDateTime(
                                data['createdAt'],
                                fallback: '업로드 시간 확인 중',
                              ),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (ownVideo)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton(
                          key: ValueKey('delete-feedback-$videoId'),
                          tooltip: '내 피드백 영상 삭제',
                          onPressed:
                              deleting ? null : () => _deleteFeedback(videoId),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: .72),
                            foregroundColor: const Color(0xFFFF8A80),
                          ),
                          icon: deleting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoUploadScreen(
                  lessonId: widget.lessonId, service: _videos),
            ),
          ),
          icon: const Icon(Icons.video_call_rounded),
          label: const Text('영상 등록'),
        ),
      );
}
