import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/video_upload_service.dart';
import '../utils/korea_time.dart';
import '../widget/video_item_widget.dart';
import 'video_upload_screen.dart';

class LessonFeedbackVideosScreen extends StatefulWidget {
  const LessonFeedbackVideosScreen({super.key, required this.lessonId});

  final String lessonId;

  @override
  State<LessonFeedbackVideosScreen> createState() =>
      _LessonFeedbackVideosScreenState();
}

class _LessonFeedbackVideosScreenState
    extends State<LessonFeedbackVideosScreen> {
  int _page = 0;
  final Map<String, Future<String>> _downloadUrls = {};
  VideoUploadService? _videoService;
  final Set<String> _deleting = <String>{};

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;
  VideoUploadService get _videos => _videoService ??= VideoUploadService();

  Future<String> _downloadUrl(String storagePath) => _downloadUrls.putIfAbsent(
        storagePath,
        () => FirebaseStorage.instance.ref(storagePath).getDownloadURL(),
      );

  Future<void> _deleteFeedback(String videoId) async {
    if (_deleting.contains(videoId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B24),
        title: const Text('피드백 영상 삭제'),
        content: const Text('내가 올린 피드백 영상을 삭제할까요? 삭제 후 복구할 수 없습니다.'),
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
          stream: FirebaseFirestore.instance
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
                    '아직 등록된 피드백 영상이 없습니다.\n아래 버튼으로 이 레슨의 참여자에게만 공개되는 영상을 등록해 보세요.',
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
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<String>(
                      future: storagePath.isEmpty
                          ? Future<String>.error('missing storage path')
                          : _downloadUrl(storagePath),
                      builder: (context, urlSnapshot) {
                        if (urlSnapshot.hasError) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '영상을 불러오지 못했습니다. 레슨 참여 권한과 연결 상태를 확인해 주세요.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        if (!urlSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return VideoItemWidget(
                          key: ValueKey(videoId),
                          videoUrl: urlSnapshot.data!,
                          fit: BoxFit.contain,
                          isPlaying: index == _page,
                        );
                      },
                    ),
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
              builder: (_) => VideoUploadScreen(lessonId: widget.lessonId),
            ),
          ),
          icon: const Icon(Icons.video_call_rounded),
          label: const Text('영상 등록'),
        ),
      );
}
