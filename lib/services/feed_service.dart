import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedService {
  FeedService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get currentUserId => _auth.currentUser?.uid;

  Stream<bool> watchLiked(String videoId) {
    final uid = currentUserId;
    if (uid == null) return Stream.value(false);
    return _firestore
        .collection('feed_videos')
        .doc(videoId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  /// Sets the intended state so retries cannot add a second like or EXP.
  Future<void> setLiked(String videoId, {required bool liked}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('로그인 후 좋아요를 누를 수 있습니다.');

    final videoRef = _firestore.collection('feed_videos').doc(videoId);
    final likeRef = videoRef.collection('likes').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final video = await transaction.get(videoRef);
      final like = await transaction.get(likeRef);
      if (!video.exists) throw StateError('삭제되었거나 존재하지 않는 영상입니다.');
      final data = video.data()!;
      final authorId = data['userId'] as String?;
      if (authorId == null || authorId.isEmpty) {
        throw StateError('영상 작성자를 확인할 수 없습니다.');
      }
      if (authorId == uid) throw StateError('내 영상에는 좋아요를 누를 수 없습니다.');

      final authorRef = _firestore.collection('users').doc(authorId);
      final author = await transaction.get(authorRef);
      if (!author.exists) throw StateError('영상 작성자의 계정을 찾을 수 없습니다.');
      if (like.exists == liked) return;

      final delta = liked ? 1 : -1;
      final videoLikes = _count(data['likes']);
      final authorLikes = _count(author.data()?['feedLikeCount']);
      transaction.update(videoRef, {'likes': _nonnegative(videoLikes + delta)});
      transaction.update(authorRef, {
        'lastFeedLikeVideoId': videoId,
        'feedLikeCount': _nonnegative(authorLikes + delta),
      });
      if (liked) {
        transaction.set(likeRef, {
          'userId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.delete(likeRef);
      }
    });
  }

  static int _count(dynamic value) =>
      value is num ? _nonnegative(value.toInt()) : 0;

  static int _nonnegative(int value) => value < 0 ? 0 : value;
}
