import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The complete lesson lifecycle uses the same lesson_requests documents.
class MatchingService {
  MatchingService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return uid;
  }

  Stream<bool> couponEligibility() => _db
      .collection('users')
      .doc(currentUid)
      .snapshots()
      .map((doc) => doc.data()?['role'] == 'student');

  Stream<QuerySnapshot<Map<String, dynamic>>> lessons() => _db
      .collection('lesson_requests')
      .where('participantIds', arrayContains: currentUid)
      .snapshots();

  /// Prefill completion with the current profile rather than a stale request.
  Future<String> currentSignatureMove({String fallback = ''}) async {
    final uid = currentUid;
    final profiles = await Future.wait([
      _db.collection('instructors').doc(uid).get(),
      _db.collection('users').doc(uid).get(),
    ]);
    return _nonEmptyString(profiles[0].data()?['signatureMove']) ??
        _nonEmptyString(profiles[1].data()?['signatureMove']) ??
        fallback.trim();
  }

  Future<void> _workflow(String name, Map<String, dynamic> data) async {
    currentUid;
    await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable(name)
        .call(data);
  }

  Future<void> acceptLesson(String id) =>
      _workflow('acceptLesson', {'lessonId': id});
  Future<void> rejectLesson(String id) =>
      _workflow('rejectLesson', {'lessonId': id});
  Future<void> cancelLesson(String id, {String? reason}) => _workflow(
      'cancelLesson', {'lessonId': id, if (reason != null) 'reason': reason});
  Future<void> respondSchedule(String id, String decision,
          {required int revision}) =>
      _workflow('respondScheduleChange',
          {'lessonId': id, 'decision': decision, 'revision': revision});
  Future<void> respondCompletion(String id, String decision,
          {required int revision, String? reason}) =>
      _workflow('respondLessonCompletion', {
        'lessonId': id,
        'decision': decision,
        'revision': revision,
        if (reason != null) 'reason': reason
      });
  Future<void> resolveDispute(String id, String decision, String reason,
          {required int revision}) =>
      _workflow('resolveLessonDispute', {
        'lessonId': id,
        'decision': decision,
        'reason': reason,
        'revision': revision
      });

  Future<void> completeLesson({
    required String requestId,
    required double reviewScore,
    String feedback = '',
    String? signatureMove,
  }) async {
    if (!reviewScore.isFinite || reviewScore < 1 || reviewScore > 5) {
      throw ArgumentError('평가 점수는 1점부터 5점까지 입력해 주세요.');
    }
    if (feedback.trim().length > 1000) {
      throw ArgumentError('피드백은 1000자 이내로 입력해 주세요.');
    }
    await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable('completeLesson')
        .call({
      'lessonId': requestId,
      'reviewScore': reviewScore,
      'feedback': feedback.trim(),
      if (signatureMove != null) 'signatureMove': signatureMove,
    });
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
