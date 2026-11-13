import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The complete lesson lifecycle uses the same lesson_requests documents.
class MatchingService {
  MatchingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

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
      if (data['status'] == status) {
        // Repair a legacy accepted lesson that was saved before its room was
        // created. Retrying acceptance is safe and idempotent.
        if (status == 'accepted') {
          transaction.set(
              _chatRoom(data), _chatRoomData(data), SetOptions(merge: true));
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
        transaction.set(
            _chatRoom(data), _chatRoomData(data), SetOptions(merge: true));
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
    final uid = currentUid;
    final ref = _db.collection('lesson_requests').doc(requestId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final coach = await transaction.get(_db.collection('users').doc(uid));
      final data = snapshot.data();
      if (data == null) throw StateError('레슨 신청을 찾을 수 없습니다.');
      if (data['instructorUid'] != uid || coach.data()?['role'] != 'coach') {
        throw StateError('담당 코치만 레슨을 완료할 수 있습니다.');
      }
      // A retry preserves both the review and the original attendance badge.
      if (data['status'] == 'completed') return;
      if (data['status'] != 'accepted') {
        throw StateError('수락한 레슨만 완료할 수 있습니다.');
      }
      final studentRef =
          _db.collection('users').doc(data['studentUid'] as String);
      final student = await transaction.get(studentRef);
      if (!student.exists) throw StateError('수강생 정보를 찾을 수 없습니다.');
      final instructorRef = _db.collection('instructors').doc(uid);
      final instructor = await transaction.get(instructorRef);
      final providedSignature = _nonEmptyString(signatureMove);
      final selectedBadgeId =
          _nonEmptyString(instructor.data()?['signatureBadgeId']) ??
              _nonEmptyString(coach.data()?['signatureBadgeId']) ??
              _nonEmptyString(data['signatureBadgeId']);
      final selectedBadge = selectedBadgeId == null
          ? null
          : await transaction
              .get(_db.collection('signature_badges').doc(selectedBadgeId));
      if (selectedBadgeId != null && selectedBadge?.exists != true) {
        throw StateError('선택한 시그니처 뱃지를 전역 목록에서 다시 등록해 주세요.');
      }
      final awardedSignature =
          _nonEmptyString(selectedBadge?.data()?['name']) ??
              _nonEmptyString(instructor.data()?['signatureMove']) ??
              _nonEmptyString(coach.data()?['signatureMove']) ??
              _nonEmptyString(data['signatureMove']);
      if (awardedSignature == null) {
        throw StateError('출석 뱃지를 지급하려면 코치의 시그니처 기술을 입력해 주세요.');
      }
      if (providedSignature != null && providedSignature != awardedSignature) {
        throw StateError('레슨 완료 전 마이페이지에서 사용할 시그니처 뱃지를 선택해 주세요.');
      }
      if (awardedSignature.length > 40) {
        throw StateError('시그니처 기술은 40자 이내로 입력해 주세요.');
      }
      final selectedBadgeColorIndex =
          (selectedBadge?.data()?['colorIndex'] as num?)?.toInt() ??
              (instructor.data()?['signatureBadgeColorIndex'] as num?)
                  ?.toInt() ??
              (coach.data()?['signatureBadgeColorIndex'] as num?)?.toInt() ??
              (data['signatureBadgeColorIndex'] as num?)?.toInt();
      final instructorName = _nonEmptyString(data['instructorName']) ??
          _nonEmptyString(instructor.data()?['name']) ??
          _nonEmptyString(coach.data()?['name']) ??
          '코치';
      final sport = _nonEmptyString(data['sport']) ??
          _nonEmptyString(instructor.data()?['sport']) ??
          _nonEmptyString(coach.data()?['sport']) ??
          '';
      final studentData = student.data()!;
      // Preserve separate reviews with identical scores.
      final scores = (studentData['reviewScores'] as List<dynamic>? ?? [])
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList();
      // All reads and validation precede writes so attendance and progress
      // either commit together or leave every record intact. Badge selection
      // is managed separately in the coach's My Page.
      transaction.update(studentRef, {
        'lastCompletedLessonId': requestId,
        'lessonCount': (studentData['lessonCount'] as num? ?? 0).toInt() + 1,
        'reviewScores': [...scores, reviewScore],
        if (data['isInstructorInitiated'] == true)
          'teacherMatchCount':
              (studentData['teacherMatchCount'] as num? ?? 0).toInt() + 1,
      });
      transaction.update(ref, {
        'status': 'completed',
        'reviewScore': reviewScore,
        'reviewFeedback': feedback.trim(),
        'attendanceBadge': {
          'instructorUid': uid,
          'instructorName': instructorName,
          'signatureMove': awardedSignature,
          if (selectedBadgeId != null) 'signatureBadgeId': selectedBadgeId,
          if (selectedBadgeColorIndex != null)
            'signatureBadgeColorIndex': selectedBadgeColorIndex,
          'sport': sport,
          'awardedAt': FieldValue.serverTimestamp(),
          'verifiedBy': uid,
        },
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(_activeRequest(data));
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
