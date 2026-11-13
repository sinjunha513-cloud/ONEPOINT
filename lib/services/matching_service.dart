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

  Future<void> acceptLesson(String requestId) =>
      _changeStatus(requestId, 'accepted');
  Future<void> rejectLesson(String requestId) =>
      _changeStatus(requestId, 'rejected');
  Future<void> cancelLesson(String requestId) =>
      _changeStatus(requestId, 'cancelled');

  Future<void> _changeStatus(String requestId, String status) async {
    final uid = currentUid;
    final ref = _db.collection('lesson_requests').doc(requestId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final actor = await transaction.get(_db.collection('users').doc(uid));
      final data = snapshot.data();
      if (data == null) throw StateError('레슨 신청을 찾을 수 없습니다.');
      final cancelling = status == 'cancelled';
      if (data[cancelling ? 'studentUid' : 'instructorUid'] != uid ||
          (!cancelling && actor.data()?['role'] != 'coach')) {
        throw StateError('이 레슨을 변경할 권한이 없습니다.');
      }
      final room =
          status == 'accepted' ? await transaction.get(_chatRoom(data)) : null;
      if (data['status'] == status) {
        // Repair a legacy accepted lesson that was saved before its room was
        // created. Retrying acceptance is safe and idempotent.
        if (status == 'accepted' && room?.exists != true) {
          transaction.set(_chatRoom(data), _chatRoomData(data));
        }
        return;
      }
      if (data['status'] != 'pending') {
        throw StateError('대기 중인 신청만 변경할 수 있습니다.');
      }
      if (status == 'accepted' && data['paymentRequired'] == true) {
        throw StateError('결제가 필요한 레슨은 결제 수락 절차를 이용해 주세요.');
      }
      transaction.update(
          ref, {'status': status, 'updatedAt': FieldValue.serverTimestamp()});
      if (status == 'accepted') {
        if (room?.exists != true) {
          transaction.set(_chatRoom(data), _chatRoomData(data));
        }
      } else {
        transaction.delete(_activeRequest(data));
      }
    });
  }

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

  DocumentReference<Map<String, dynamic>> _activeRequest(
      Map<String, dynamic> data) {
    return _db.collection('active_lesson_requests').doc(
        '${data['instructorUid'] as String}_${data['studentUid'] as String}');
  }

  DocumentReference<Map<String, dynamic>> _chatRoom(Map<String, dynamic> data) {
    final ids = [data['studentUid'] as String, data['instructorUid'] as String]
      ..sort();
    return _db.collection('chat_rooms').doc(ids.join('_'));
  }

  Map<String, dynamic> _chatRoomData(Map<String, dynamic> lesson) {
    final studentUid = lesson['studentUid'] as String;
    final coachUid = lesson['instructorUid'] as String;
    final ids = [studentUid, coachUid]..sort();
    return {
      'participantIds': ids,
      'studentUid': studentUid,
      'studentName': _nonEmptyString(lesson['studentName']) ?? '수강생',
      'coachUid': coachUid,
      'coachName': _nonEmptyString(lesson['instructorName']) ?? '코치',
    };
  }
}
