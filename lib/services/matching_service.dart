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

  Stream<bool> lessonTestMode() => _db
      .doc('app_config/features')
      .snapshots()
      .map((doc) => doc.data()?['lessonTestModeEnabled'] == true);

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

String lessonWorkflowError(Object error) {
  if (error is ArgumentError) return error.message.toString();
  if (error is StateError) return error.message.toString();
  if (error is FirebaseFunctionsException) {
    final message = error.message?.trim() ?? '';
    if (!['internal', 'unknown'].contains(error.code) &&
        RegExp(r'[가-힣]').hasMatch(message) &&
        !message.contains('요청을 처리하지 못')) {
      return message;
    }
    return switch (error.code) {
      'unauthenticated' => '로그인한 뒤 다시 시도해 주세요.',
      'permission-denied' => '이 레슨을 처리할 권한이 없습니다.',
      'invalid-argument' => '레슨 정보와 입력한 내용을 확인해 주세요.',
      'failed-precondition' => '레슨 상태와 예정 종료 시각을 확인해 주세요.',
      'not-found' => '레슨 정보를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
      'already-exists' => '이미 접수된 레슨 요청입니다. 최신 내역을 확인해 주세요.',
      'aborted' => '레슨 정보가 변경되었습니다. 최신 내역을 확인하고 다시 시도해 주세요.',
      'unavailable' ||
      'deadline-exceeded' =>
        '레슨 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      _ => '레슨 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  return '레슨 요청을 처리하지 못했습니다. 연결 상태를 확인해 주세요.';
}
