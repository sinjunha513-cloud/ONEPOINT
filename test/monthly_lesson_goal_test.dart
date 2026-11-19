import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/models/monthly_lesson_goal.dart';

void main() {
  final now = DateTime.utc(2026, 11, 19);
  Map<String, dynamic> lesson(String student, String coach, String time,
          {String status = 'completed'}) =>
      {
        'studentUid': student,
        'instructorUid': coach,
        'status': status,
        'completedAt': Timestamp.fromDate(DateTime.parse(time)),
      };
  test('Korean calendar month uses completion time and current role', () {
    final lessons = [
      lesson('me', 'other', '2026-10-31T14:59:59Z'),
      lesson('me', 'other', '2026-10-31T15:00:00Z'),
      lesson('me', 'other', '2026-11-18T12:00:00Z'),
      lesson('other', 'me', '2026-11-18T12:00:00Z'),
      lesson('me', 'other', '2026-11-18T12:00:00Z', status: 'accepted'),
      lesson('me', 'other', '2026-11-30T15:00:00Z'),
      {'studentUid': 'me', 'status': 'completed'},
    ];
    final student = MonthlyLessonGoal(
        lessons: lessons, uid: 'me', role: 'student', now: now);
    expect(student.count, 2);
    expect(student.percent, 10);
    expect(student.remainingPercent, 90);
    expect(student.remainingLessons, 18);
    expect(student.monthKey, '202611');
    expect(
        MonthlyLessonGoal(lessons: lessons, uid: 'me', role: 'coach', now: now)
            .count,
        1);
    expect(
        MonthlyLessonGoal(lessons: lessons, uid: 'me', role: 'admin', now: now)
            .count,
        0);
  });
  test(
      'twenty and more completed lessons cap at 100 percent and next month resets',
      () {
    final lessons =
        List.generate(22, (_) => lesson('me', 'coach', '2026-11-18T12:00:00Z'));
    final goal = MonthlyLessonGoal(
        lessons: lessons, uid: 'me', role: 'student', now: now);
    expect(goal.count, 22);
    expect(goal.percent, 100);
    expect(goal.remainingLessons, 0);
    expect(goal.achieved, true);
    final nineteen = MonthlyLessonGoal(
        lessons: lessons.take(19), uid: 'me', role: 'student', now: now);
    expect(nineteen.percent, 95);
    expect(nineteen.achieved, false);
    expect(nineteen.remainingLessons, 1);
    final coach = MonthlyLessonGoal(
        lessons: List.generate(
            22, (_) => lesson('other', 'me', '2026-11-18T12:00:00Z')),
        uid: 'me',
        role: 'coach',
        now: now);
    expect(coach.count, 22);
    expect(coach.eligible, false);
    expect(coach.achieved, false);
    expect(coach.percent, 0);
    expect(
        MonthlyLessonGoal(
                lessons: lessons,
                uid: 'me',
                role: 'student',
                now: DateTime.utc(2026, 11, 30, 15))
            .count,
        0);
  });
}
