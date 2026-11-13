import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'instructor_service.dart';
import '../config/sports.dart';

class LessonService {
  LessonService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;

  FirebaseFunctions get _api =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  InstructorService get _instructors =>
      InstructorService(firestore: _db, auth: _auth);

  Stream<QuerySnapshot<Map<String, dynamic>>> getInstructors(String sport) =>
      _instructors.approvedInstructors(sport);

  Future<void> registerInstructor({
    required String name,
    required String sport,
    required String career,
    required String rating,
    String? signatureMove,
  }) =>
      _instructors.registerInstructor(
        name: name,
        sport: sport,
        career: career,
        rating: rating,
        signatureMove: signatureMove,
      );

  Future<String> requestLesson({
    required String instructorId,
    required String instructorName,
    required String? coachUid,
    String? slotId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    if (coachUid == null || coachUid.isEmpty || coachUid != instructorId) {
      throw StateError('코치 계정 정보를 확인할 수 없습니다.');
    }
    if (coachUid == user.uid) {
      throw StateError('본인에게 레슨을 신청할 수 없습니다.');
    }
    if (slotId != null) {
      final result = await _api.httpsCallable('requestLessonWithSlot').call({
        'instructorId': instructorId,
        'slotId': slotId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['lessonId'] as String;
    }
    final request = _db.collection('lesson_requests').doc();
    final ids = [user.uid, coachUid]..sort();
    // One active request per student/coach pair, including concurrent taps.
    final activeRequest =
        _db.collection('active_lesson_requests').doc('${coachUid}_${user.uid}');
    await _db.runTransaction((transaction) async {
      final student =
          await transaction.get(_db.collection('users').doc(user.uid));
      final instructor = await transaction
          .get(_db.collection('instructors').doc(instructorId));
      final coach =
          await transaction.get(_db.collection('users').doc(coachUid));
      final active = await transaction.get(activeRequest);
      final requesterRole = _nonEmptyString(student.data()?['role']);
      if (!student.exists ||
          (requesterRole != 'student' && requesterRole != 'admin')) {
        throw StateError('수강생 또는 관리자 계정에서 레슨을 신청해 주세요.');
      }
      if (!instructor.exists ||
          !supportedSports.contains(instructor.data()?['sport']) ||
          instructor.data()?['status'] != 'approved' ||
          instructor.data()?['uid'] != coachUid ||
          coach.data()?['role'] != 'coach') {
        throw StateError('현재 신청할 수 없는 코치입니다.');
      }
      if (active.exists) {
        throw StateError('이미 신청했거나 진행 중인 레슨이 있습니다. 내 레슨을 확인해 주세요.');
      }
      final studentName =
          student.data()?['name'] as String? ?? user.displayName ?? '수강생';
      final coachName = instructor.data()?['name'] as String? ?? instructorName;
      final signatureMove =
          _nonEmptyString(instructor.data()?['signatureMove']) ??
              _nonEmptyString(coach.data()?['signatureMove']);
      final signatureBadgeId =
          _nonEmptyString(instructor.data()?['signatureBadgeId']) ??
              _nonEmptyString(coach.data()?['signatureBadgeId']);
      final signatureBadgeColorIndex =
          (instructor.data()?['signatureBadgeColorIndex'] as num?)?.toInt() ??
              (coach.data()?['signatureBadgeColorIndex'] as num?)?.toInt();
      transaction.set(request, {
        'instructorId': instructorId,
        'instructorUid': coachUid,
        'instructorName': coachName,
        'sport': _nonEmptyString(instructor.data()?['sport']) ??
            _nonEmptyString(coach.data()?['sport']) ??
            '',
        if (signatureMove != null) 'signatureMove': signatureMove,
        if (signatureBadgeId != null) 'signatureBadgeId': signatureBadgeId,
        if (signatureBadgeColorIndex != null)
          'signatureBadgeColorIndex': signatureBadgeColorIndex,
        'studentUid': user.uid,
        'studentName': studentName,
        'participantIds': ids,
        'status': 'pending',
        // The normal matching flow does not depend on the optional payment
        // prototype. The assigned coach can accept this request directly.
        'paymentRequired': false,
        'isInstructorInitiated': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(activeRequest, {
        'requestId': request.id,
        'participantIds': ids,
      });
    });
    return request.id;
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
