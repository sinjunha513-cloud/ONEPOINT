import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/lesson_requests_screen.dart';
import 'package:onepoint_lesson/services/matching_service.dart';
import 'support/fake_functions.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  Future<void> addLesson({
    String id = 'lesson',
    String studentUid = 'student',
    String instructorUid = 'coach',
    String instructorName = '민수',
    int createdSeconds = 100,
  }) async {
    await firestore.collection('lesson_requests').doc(id).set({
      'studentUid': studentUid,
      'studentName': '지우',
      'instructorUid': instructorUid,
      'instructorName': instructorName,
      'signatureMove': '라 크로케타',
      'participantIds': [studentUid, instructorUid],
      'status': 'pending',
      'createdAt': Timestamp(createdSeconds, 0),
    });
  }

  Future<void> showLessons(WidgetTester tester, String uid,
      {Size size = const Size(900, 1000), double textScale = 1}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LessonRequestsScreen(
        service: MatchingService(
          firestore: firestore,
          functions: FakeFunctions((name, data) async {
            expect(name, 'completeLesson');
            // Fixed server response fixture. Domain and authorization tests run
            // against the actual callable handlers in the Emulator suite.
            await firestore.collection('lesson_requests').doc('lesson').update({
              'status': 'completed',
              'reviewScore': data['reviewScore'],
              'reviewFeedback': data['feedback'],
              'attendanceBadge': {
                'signatureMove': data['signatureMove'],
                'verifiedBy': 'coach'
              },
            });
            await firestore.collection('users').doc('student').update({
              'lessonCount': 2,
              'reviewScores': [4.0, 4.0],
            });
            return {'lessonId': 'lesson', 'status': 'completed'};
          }),
          auth: MockFirebaseAuth(
            mockUser: MockUser(uid: uid),
            signedIn: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('student').set({
      'name': '지우',
      'role': 'student',
      'lessonCount': 1,
      'reviewScores': [4.0],
    });
    await firestore.collection('users').doc('coach').set({
      'name': '민수',
      'role': 'coach',
    });
  });

  testWidgets('student can cancel a pending lesson but cannot coach it',
      (tester) async {
    await addLesson();
    await firestore
        .collection('active_lesson_requests')
        .doc('coach_student')
        .set({
      'requestId': 'lesson',
    });
    await showLessons(tester, 'student');

    expect(find.text('민수 코치'), findsOneWidget);
    expect(find.text('수락 대기'), findsOneWidget);
    expect(find.text('신청 취소'), findsOneWidget);
    expect(find.text('수락'), findsNothing);
    expect(find.text('거절'), findsNothing);
    expect(find.text('레슨 완료 및 평가'), findsNothing);
    expect(find.text('채팅'), findsNothing);

    await tester.tap(find.text('신청 취소'));
    await tester.pumpAndSettle();

    expect(find.text('취소됨'), findsOneWidget);
    expect(find.text('신청 취소'), findsNothing);
    expect(
      (await firestore.collection('lesson_requests').doc('lesson').get())
          .data()!['status'],
      'cancelled',
    );
    expect(
      (await firestore
              .collection('active_lesson_requests')
              .doc('coach_student')
              .get())
          .exists,
      isFalse,
    );
    expect(
      (await firestore.collection('users').doc('student').get())
          .data()!['lessonCount'],
      1,
    );
  });

  testWidgets('coach accepts and evaluates a lesson, updating progress once',
      (tester) async {
    await addLesson();
    await showLessons(tester, 'coach');

    expect(find.text('지우 수강생'), findsOneWidget);
    expect(find.text('신청 취소'), findsNothing);
    await tester.tap(find.text('수락'));
    await tester.pumpAndSettle();
    expect(find.text('진행 중'), findsOneWidget);
    expect(find.text('수락'), findsNothing);
    expect(find.text('거절'), findsNothing);
    expect(find.text('채팅'), findsOneWidget);
    expect(
      (await firestore.collection('chat_rooms').doc('coach_student').get())
          .exists,
      isTrue,
    );

    await tester.tap(find.text('레슨 완료 및 평가'));
    // The lesson stays busy while the dialog is open, so its progress
    // indicator intentionally continues animating beneath the dialog.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('평가하고 완료'));
    await tester.pump();
    expect(find.text('평가 점수를 선택해 주세요.'), findsOneWidget);
    expect(
      (await firestore.collection('lesson_requests').doc('lesson').get())
          .data()!['status'],
      'accepted',
    );

    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('4점').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.byKey(const ValueKey('lesson-feedback')), '패스 정확도가 좋아졌어요.');
    // A score alone must never issue an attendance badge.
    await tester.tap(find.text('평가하고 완료'));
    await tester.pump();
    expect(find.text('실제 레슨 참여 여부를 확인해 주세요.'), findsOneWidget);
    final unconfirmed =
        (await firestore.collection('lesson_requests').doc('lesson').get())
            .data()!;
    expect(unconfirmed['status'], 'accepted');
    expect(unconfirmed.containsKey('attendanceBadge'), isFalse);
    await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester
        .tap(find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester.pump();
    await tester.tap(find.text('평가하고 완료'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('수강생 평가: 4.0 / 5'), findsOneWidget);
    expect(find.text('패스 정확도가 좋아졌어요.'), findsOneWidget);
    expect(find.text('레슨 완료 및 평가'), findsNothing);
    final lesson =
        (await firestore.collection('lesson_requests').doc('lesson').get())
            .data()!;
    final student =
        (await firestore.collection('users').doc('student').get()).data()!;
    expect(lesson['status'], 'completed');
    expect(lesson['reviewScore'], 4.0);
    expect(lesson['reviewFeedback'], '패스 정확도가 좋아졌어요.');
    expect(lesson['attendanceBadge']['signatureMove'], '라 크로케타');
    expect(lesson['attendanceBadge']['verifiedBy'], 'coach');
    expect(find.text('참여 확인 완료 · 출석 뱃지 지급'), findsOneWidget);
    expect(student['lessonCount'], 2);
    expect(student['reviewScores'], [4.0, 4.0]);

    // Further live snapshots must leave the completed lesson read-only.
    await firestore.collection('lesson_requests').doc('lesson').update({
      'updatedAt': Timestamp(200, 0),
    });
    await tester.pumpAndSettle();
    expect(find.text('레슨 완료 및 평가'), findsNothing);
    expect(
      (await firestore.collection('users').doc('student').get())
          .data()!['lessonCount'],
      2,
    );
  });

  testWidgets('coach can reject a pending lesson without awarding progress',
      (tester) async {
    await addLesson();
    await showLessons(tester, 'coach');

    await tester.tap(find.text('거절'));
    await tester.pumpAndSettle();

    expect(find.text('거절됨'), findsOneWidget);
    expect(find.text('수락'), findsNothing);
    expect(find.text('레슨 완료 및 평가'), findsNothing);
    expect(
      (await firestore.collection('lesson_requests').doc('lesson').get())
          .data()!['status'],
      'rejected',
    );
    expect(
      (await firestore.collection('users').doc('student').get())
          .data()!['lessonCount'],
      1,
    );
  });

  testWidgets('missing signature directs the coach to My Page management',
      (tester) async {
    await addLesson();
    await firestore.collection('lesson_requests').doc('lesson').update({
      'signatureMove': FieldValue.delete(),
      'status': 'accepted',
    });
    await showLessons(tester, 'coach');
    await tester.tap(find.text('레슨 완료 및 평가'));
    await tester.pump();

    expect(find.text('마이페이지의 시그니처 뱃지 관리에서 뱃지를 먼저 등록해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-signature-move')), findsNothing);

    final data =
        (await firestore.collection('lesson_requests').doc('lesson').get())
            .data()!;
    expect(data['attendanceBadge'], isNull);
    expect(data['status'], 'accepted');
  });

  testWidgets('completion uses the latest coach signature for an older request',
      (tester) async {
    await addLesson();
    await firestore.collection('lesson_requests').doc('lesson').update({
      'status': 'accepted',
    });
    await firestore.collection('instructors').doc('coach').set({
      'signatureMove': '감아차기',
    });
    await showLessons(tester, 'coach');
    await tester.tap(find.text('레슨 완료 및 평가'));
    await tester.pump(const Duration(milliseconds: 400));
    final signatureField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('lesson-signature-move')));
    expect(signatureField.controller!.text, '감아차기');
    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('4점').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester
        .tap(find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester.tap(find.text('평가하고 완료'));
    await tester.pumpAndSettle();

    final lesson =
        (await firestore.collection('lesson_requests').doc('lesson').get())
            .data()!;
    final instructor =
        (await firestore.collection('instructors').doc('coach').get()).data()!;
    expect(lesson['attendanceBadge']['signatureMove'], '감아차기');
    expect(instructor['signatureMove'], '감아차기');
  });

  testWidgets(
      'attendance dialog stays usable on a narrow screen with large text',
      (tester) async {
    await addLesson();
    await firestore.collection('lesson_requests').doc('lesson').update({
      'status': 'accepted',
    });
    await showLessons(tester, 'coach',
        size: const Size(320, 640), textScale: 1.5);
    await tester.tap(find.text('레슨 완료 및 평가'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
        find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester
        .tap(find.byKey(const ValueKey('lesson-attendance-confirmation')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final lesson =
        (await firestore.collection('lesson_requests').doc('lesson').get())
            .data()!;
    expect(lesson['status'], 'accepted');
    expect(lesson.containsKey('attendanceBadge'), isFalse);
  });

  testWidgets('only own lessons appear and newest requests are first',
      (tester) async {
    await addLesson(id: 'old', instructorName: '이전 코치', createdSeconds: 100);
    await addLesson(id: 'new', instructorName: '최근 코치', createdSeconds: 200);
    await addLesson(
      id: 'unrelated',
      studentUid: 'other-student',
      instructorUid: 'other-coach',
      instructorName: '다른 코치',
      createdSeconds: 300,
    );
    await showLessons(tester, 'student');

    expect(find.text('다른 코치 코치'), findsNothing);
    expect(find.byType(Card), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('최근 코치 코치')).dy,
      lessThan(tester.getTopLeft(find.text('이전 코치 코치')).dy),
    );
  });

  testWidgets('a member without lessons sees the empty state', (tester) async {
    await addLesson(studentUid: 'other-student', instructorUid: 'other-coach');
    await showLessons(tester, 'student');

    expect(find.textContaining('아직 레슨 내역이 없습니다.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
