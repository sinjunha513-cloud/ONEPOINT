import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedService {
  FeedService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;

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

    await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable('setFeedLiked')
        .call({'videoId': videoId, 'liked': liked});
  }
}
