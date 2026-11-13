import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lesson_slot.dart';

class CoachAvailabilityService {
  CoachAvailabilityService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _slots(String coachUid) =>
      _db.collection('instructors').doc(coachUid).collection(
          coachUid == currentUid ? 'availability' : 'public_availability');

  Stream<List<LessonSlot>> slotsForCoach(String coachUid,
      {bool availableOnly = false}) {
    return _slots(coachUid).snapshots().map((snapshot) {
      final slots = snapshot.docs
          .map((doc) {
            try {
              return LessonSlot.fromDocument(doc);
            } on FormatException {
              return null;
            }
          })
          .whereType<LessonSlot>()
          .where(
              (slot) => !availableOnly || (slot.isAvailable && slot.isFuture))
          .toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      return slots;
    });
  }

  Stream<List<LessonSlot>> mySlots() => slotsForCoach(currentUid);

  Future<String> saveSlot({
    String? slotId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final result = await _functions.httpsCallable('saveAvailabilitySlot').call({
      if (slotId != null) 'slotId': slotId,
      'startAtMillis': startAt.toUtc().millisecondsSinceEpoch,
      'endAtMillis': endAt.toUtc().millisecondsSinceEpoch,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['slotId'] as String;
  }

  Future<List<String>> saveSlots(
    List<({DateTime startAt, DateTime endAt})> ranges,
  ) async {
    if (ranges.isEmpty || ranges.length > 100) {
      throw StateError('가능 시간은 한 번에 1개 이상 100개 이하로 등록해 주세요.');
    }
    final result =
        await _functions.httpsCallable('saveAvailabilitySlots').call({
      'slots': [
        for (final range in ranges)
          {
            'startAtMillis': range.startAt.toUtc().millisecondsSinceEpoch,
            'endAtMillis': range.endAt.toUtc().millisecondsSinceEpoch,
          },
      ],
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['slotIds'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<void> deleteSlot(String slotId) async {
    await _functions
        .httpsCallable('deleteAvailabilitySlot')
        .call({'slotId': slotId});
  }

  Future<void> rescheduleLesson(String lessonId, String slotId) async {
    await _functions.httpsCallable('rescheduleLesson').call({
      'lessonId': lessonId,
      'slotId': slotId,
    });
  }

  Stream<List<LessonScheduleChange>> scheduleHistory(String lessonId) => _db
      .collection('lesson_requests')
      .doc(lessonId)
      .collection('schedule_changes')
      .orderBy('changedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) {
            try {
              return LessonScheduleChange.fromDocument(doc);
            } on FormatException {
              return null;
            }
          })
          .whereType<LessonScheduleChange>()
          .toList(growable: false));
}

String availabilityError(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message ?? '';
    if (RegExp(r'[가-힣]').hasMatch(message)) return message;
    return switch (error.code) {
      'unauthenticated' => '로그인한 뒤 다시 시도해 주세요.',
      'permission-denied' => '레슨 일정을 변경할 권한이 없습니다.',
      'not-found' => '선택한 가능 시간 또는 레슨을 찾을 수 없습니다.',
      'already-exists' => '해당 시간대에 이미 다른 레슨이 예약됐습니다.',
      'failed-precondition' => '이미 마감됐거나 변경할 수 없는 일정입니다.',
      'invalid-argument' => '날짜와 시간을 다시 확인해 주세요.',
      'unavailable' ||
      'deadline-exceeded' =>
        '일정 서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      _ => '레슨 일정을 처리하지 못했습니다. 다시 시도해 주세요.',
    };
  }
  if (error is StateError) return error.message.toString();
  return '레슨 일정을 처리하지 못했습니다. 다시 시도해 주세요.';
}
