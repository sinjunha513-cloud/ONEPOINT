import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/feed_service.dart';
import '../services/video_upload_service.dart';
import '../widget/video_item_widget.dart';
import 'video_upload_screen.dart';

class ShortformFeedScreen extends StatefulWidget {
  const ShortformFeedScreen({
    super.key,
    this.isActive = true,
    this.firestore,
    this.feedService,
    this.videoService,
  });

  final bool isActive;
  final FirebaseFirestore? firestore;
  final FeedService? feedService;
  final VideoUploadService? videoService;

  @override
  State<ShortformFeedScreen> createState() => _ShortformFeedScreenState();
}

class _ShortformFeedScreenState extends State<ShortformFeedScreen> {
  int _currentPage = 0;
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FeedService _feedService = widget.feedService ?? FeedService();
  VideoUploadService? _videoService;
  final Set<String> _deleting = <String>{};

  VideoUploadService get _videos =>
      _videoService ??= widget.videoService ?? VideoUploadService();

  Future<void> _deleteFeedVideo(
    String videoId,
    String title,
  ) async {
    if (_deleting.contains(videoId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B24),
        title: const Text('숏폼 영상 삭제'),
        content: Text(
          title.trim().isEmpty
              ? '이 영상을 삭제할까요? 삭제한 영상은 복구할 수 없습니다.'
              : '“$title” 영상을 삭제할까요? 삭제한 영상은 복구할 수 없습니다.',
        ),
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
      await _videos.deleteFeedVideo(videoId);
      if (!mounted) return;
      setState(() => _currentPage = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숏폼 영상을 삭제했습니다.')),
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
        appBar: AppBar(title: const Text('원포인트 피드')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('feed_videos')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('피드를 불러오지 못했습니다.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.video_library_outlined, size: 52),
                      SizedBox(height: 14),
                      Text(
                        '등록된 영상이 없습니다.\n영상 추가 버튼으로 첫 숏폼을 올려 보세요.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return PageView.builder(
              key: ValueKey('shortform-pages-${docs.length}'),
              scrollDirection: Axis.vertical,
              pageSnapping: true,
              physics: const BouncingScrollPhysics(),
              itemCount: docs.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final url = data['videoUrl'] as String? ?? '';
                final videoId = docs[index].id;
                final authorId = data['userId'] as String? ?? '';
                final ownVideo = authorId == _feedService.currentUserId;
                final deleting = _deleting.contains(videoId);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final maxVideoWidth = math.min(
                        380.0, math.max(180.0, constraints.maxWidth - 32));
                    final maxVideoHeight = math.min(
                      560.0,
                      math.max(190.0, constraints.maxHeight * .60),
                    );
                    final videoHeight = math.min(
                      maxVideoHeight,
                      maxVideoWidth * 16 / 9,
                    );
                    final videoWidth = math.min(
                      maxVideoWidth,
                      videoHeight * 9 / 16,
                    );
                    final contentWidth = math.min(
                      maxVideoWidth,
                      math.max(videoWidth, 300.0),
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: contentWidth,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.swipe_vertical_rounded,
                                  size: 18,
                                  color: Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    '위아래로 넘겨서 보기',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${index + 1} / ${docs.length}',
                                  style: const TextStyle(
                                    color: Color(0xFFBAE6FD),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            key: ValueKey('shortform-card-$videoId'),
                            width: videoWidth,
                            height: videoHeight,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF334155),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 24,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: VideoItemWidget(
                              key: ValueKey(videoId),
                              videoUrl: url,
                              fit: BoxFit.contain,
                              isPlaying:
                                  widget.isActive && index == _currentPage,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: contentWidth,
                            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171B24),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF2B3545),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        data['userName'] as String? ?? '사용자',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFBAE6FD),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        data['title'] as String? ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if ((data['description'] as String? ?? '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          data['description'] as String,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _FeedLikeButton(
                                  key: ValueKey('like-$videoId'),
                                  service: _feedService,
                                  videoId: videoId,
                                  authorId: authorId,
                                  likes: (data['likes'] as num?)?.toInt() ?? 0,
                                ),
                                if (ownVideo) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    key: ValueKey('delete-feed-$videoId'),
                                    tooltip: '내 영상 삭제',
                                    onPressed: deleting
                                        ? null
                                        : () => _deleteFeedVideo(
                                              videoId,
                                              data['title'] as String? ?? '',
                                            ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.redAccent
                                          .withValues(alpha: .14),
                                      foregroundColor: const Color(0xFFFF8A80),
                                    ),
                                    icon: deleting
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF38BDF8),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VideoUploadScreen()),
          ),
          icon: const Icon(Icons.add_rounded, color: Colors.black),
          label: const Text(
            '영상 추가',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          ),
        ),
      );
}

class _FeedLikeButton extends StatefulWidget {
  const _FeedLikeButton({
    super.key,
    required this.service,
    required this.videoId,
    required this.authorId,
    required this.likes,
  });

  final FeedService service;
  final String videoId;
  final String authorId;
  final int likes;

  @override
  State<_FeedLikeButton> createState() => _FeedLikeButtonState();
}

class _FeedLikeButtonState extends State<_FeedLikeButton> {
  late final Stream<bool> _likedStream;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _likedStream = widget.service.watchLiked(widget.videoId);
  }

  Future<void> _setLiked(bool liked) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.service.setLiked(widget.videoId, liked: liked);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is StateError
            ? error.message.toString()
            : '좋아요를 저장하지 못했습니다. 다시 시도해 주세요.'),
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: _likedStream,
        builder: (context, snapshot) {
          final isOwnVideo = widget.authorId == widget.service.currentUserId;
          final isSignedIn = widget.service.currentUserId != null;
          final liked = snapshot.data ?? false;
          final canLike = isSignedIn &&
              !isOwnVideo &&
              snapshot.hasData &&
              !snapshot.hasError &&
              !_isSaving;
          final tooltip = !isSignedIn
              ? '로그인 후 좋아요를 누를 수 있습니다.'
              : isOwnVideo
                  ? '내 영상에는 좋아요를 누를 수 없습니다.'
                  : snapshot.hasError
                      ? '좋아요 상태를 불러오지 못했습니다.'
                      : liked
                          ? '좋아요 취소'
                          : '좋아요';
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: tooltip,
                    child: IconButton(
                      onPressed: canLike ? () => _setLiked(!liked) : null,
                      color: liked ? Colors.pinkAccent : Colors.white,
                      disabledColor: Colors.white54,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(liked
                              ? Icons.favorite
                              : snapshot.hasError
                                  ? Icons.error_outline
                                  : Icons.favorite_border),
                    ),
                  ),
                  Text(
                    '${widget.likes < 0 ? 0 : widget.likes}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
