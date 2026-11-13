import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/korea_time.dart';

class LessonSlot {
  const LessonSlot({
    required this.id,
    required this.coachUid,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.lessonId,
    this.studentUid,
  });

  final String id;
  final String coachUid;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final String? lessonId;
  final String? studentUid;

  bool get isAvailable => status == 'available';
  bool get isFuture => startAt.isAfter(DateTime.now().toUtc());

  factory LessonSlot.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final start = timestampDate(data?['startAt']);
    final end = timestampDate(data?['endAt']);
    if (data == null || start == null || end == null) {
      throw const FormatException('레슨 가능 시간 정보가 올바르지 않습니다.');
    }
    return LessonSlot(
      id: document.id,
      coachUid: data['coachUid'] as String? ?? '',
      startAt: start.toUtc(),
      endAt: end.toUtc(),
      status: data['status'] as String? ?? 'available',
      lessonId: data['lessonId'] as String?,
      studentUid: data['studentUid'] as String?,
    );
  }
}

class LessonScheduleChange {
  const LessonScheduleChange({
    required this.id,
    required this.changedBy,
    required this.changedByName,
    required this.newStartAt,
    required this.newEndAt,
    this.previousStartAt,
    this.previousEndAt,
    this.changedAt,
  });

  final String id;
  final String changedBy;
  final String changedByName;
  final DateTime? previousStartAt;
  final DateTime? previousEndAt;
  final DateTime newStartAt;
  final DateTime newEndAt;
  final DateTime? changedAt;

  factory LessonScheduleChange.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final start = timestampDate(data['newStartAt']);
    final end = timestampDate(data['newEndAt']);
    if (start == null || end == null) {
      throw const FormatException('일정 변경 기록이 올바르지 않습니다.');
    }
    return LessonScheduleChange(
      id: document.id,
      changedBy: data['changedBy'] as String? ?? '',
      changedByName: data['changedByName'] as String? ?? '레슨 참여자',
      previousStartAt: timestampDate(data['previousStartAt']),
      previousEndAt: timestampDate(data['previousEndAt']),
      newStartAt: start,
      newEndAt: end,
      changedAt: timestampDate(data['changedAt']),
    );
  }
}
