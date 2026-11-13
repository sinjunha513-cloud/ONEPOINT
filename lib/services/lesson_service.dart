import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'instructor_service.dart';

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
    final result = await _api.httpsCallable('requestLesson').call({
      'instructorId': instructorId,
    });
    return Map<String, dynamic>.from(result.data as Map)['lessonId'] as String;
  }
}
