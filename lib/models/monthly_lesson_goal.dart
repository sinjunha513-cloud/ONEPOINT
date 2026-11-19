import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyLessonGoal {
  MonthlyLessonGoal(
      {required Iterable<Map<String, dynamic>> lessons,
      required String uid,
      required String role,
      DateTime? now}) {
    final utc = (now ?? DateTime.now()).toUtc();
    eligible = role == 'student';
    final korea = utc.add(const Duration(hours: 9));
    monthKey = '${korea.year}${korea.month.toString().padLeft(2, '0')}';
    monthLabel = '${korea.month}월';
    final start = DateTime.utc(korea.year, korea.month)
        .subtract(const Duration(hours: 9));
    final end = DateTime.utc(korea.year, korea.month + 1)
        .subtract(const Duration(hours: 9));
    final actor = role == 'coach' ? 'instructorUid' : 'studentUid';
    count = ['student', 'coach'].contains(role)
        ? lessons.where((lesson) {
            final completedAt = lesson['completedAt'];
            final date =
                completedAt is Timestamp ? completedAt.toDate().toUtc() : null;
            return lesson[actor] == uid &&
                lesson['status'] == 'completed' &&
                date != null &&
                !date.isBefore(start) &&
                date.isBefore(end) &&
                !date.isAfter(utc);
          }).length
        : 0;
  }
  static const target = 20;
  late final bool eligible;
  late final String monthKey;
  late final String monthLabel;
  late final int count;
  int get percent => (count * 100 ~/ target).clamp(0, 100);
  int get remainingPercent => 100 - percent;
  int get remainingLessons => (target - count).clamp(0, target);
  bool get targetReached => count >= target;
  bool get achieved => eligible && targetReached;
}
