import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/instructor_service.dart';
import 'package:onepoint_lesson/services/lesson_service.dart';
import 'package:onepoint_lesson/services/lesson_badge_service.dart';
import 'package:onepoint_lesson/services/matching_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  MockFirebaseAuth authFor(String uid) => MockFirebaseAuth(
        mockUser:
            MockUser(uid: uid, displayName: 'Authentication display name'),
        signedIn: true,
      );

  LessonService requestsFor(String uid) => LessonService(
        firestore: firestore,
        auth: authFor(uid),
      );

  MatchingService matchingFor(String uid) => MatchingService(
        firestore: firestore,
        auth: authFor(uid),
      );

  Future<String> requestLesson({String studentUid = 'student'}) async {
    await requestsFor(studentUid).requestLesson(
      instructorId: 'coach',
      instructorName: 'Outdated name from the screen',
      coachUid: 'coach',
    );
    final active = await firestore
        .collection('active_lesson_requests')
        .doc('coach_$studentUid')
        .get();
    return active.data()!['requestId'] as String;
  }

  Future<Map<String, dynamic>> studentData() async =>
      (await firestore.collection('users').doc('student').get()).data()!;

  Future<void> expectNoRequests() async {
    for (final collection in [
      'lesson_requests',
      'active_lesson_requests',
      'chat_rooms',
    ]) {
      expect((await firestore.collection(collection).get()).docs, isEmpty);
    }
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('student').set({
      'role': 'student',
      'name': '실제 수강생',
      'lessonCount': 2,
      'reviewScores': [3.0],
      'teacherMatchCount': 1,
    });
    await firestore.collection('users').doc('coach').set({
      'role': 'coach',
      'name': '코치 계정 이름',
    });
    await firestore.collection('users').doc('other-coach').set({
      'role': 'coach',
      'name': '다른 코치',
    });
    await firestore.collection('users').doc('other-student').set({
      'role': 'student',
      'name': '다른 수강생',
    });
    await firestore.collection('users').doc('admin').set({
      'role': 'admin',
      'name': '관리자',
      'lessonCount': 0,
      'reviewScores': <double>[],
      'teacherMatchCount': 0,
    });
    await firestore.collection('instructors').doc('coach').set({
      'uid': 'coach',
      'userId': 'coach',
      'name': '승인된 코치',
      'sport': '축구',
      'signatureMove': '인사이드 패스',
      'status': 'approved',
    });
  });

  group('current signature for attendance confirmation', () {
    test(
        'current instructor signature takes priority over account and fallback',
        () async {
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': '  현재 코치 기술  ',
      });
      await firestore.collection('users').doc('coach').update({
        'signatureMove': '계정 기술',
      });

      expect(
        await matchingFor('coach').currentSignatureMove(fallback: '신청 당시 기술'),
        '현재 코치 기술',
      );
    });

    test('legacy account signature is used when instructor signature is blank',
        () async {
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': '   ',
      });
      await firestore.collection('users').doc('coach').update({
        'signatureMove': '  계정 기술  ',
      });

      expect(
        await matchingFor('coach').currentSignatureMove(fallback: '신청 당시 기술'),
        '계정 기술',
      );
    });

    test('missing profile signature uses trimmed fallback or empty form value',
        () async {
      await firestore.collection('instructors').doc('coach').delete();
      final service = matchingFor('coach');

      expect(
        await service.currentSignatureMove(fallback: '  신청 당시 기술  '),
        '신청 당시 기술',
      );
      expect(await service.currentSignatureMove(), isEmpty);
      expect(await service.currentSignatureMove(fallback: '   '), isEmpty);
    });

    test('signed out lookup requires authentication', () async {
      final service = MatchingService(
        firestore: firestore,
        auth: MockFirebaseAuth(),
      );

      await expectLater(
        service.currentSignatureMove(fallback: '신청 당시 기술'),
        throwsStateError,
      );
    });
  });

  group('lesson requests', () {
    test('stores real profile names and waits for acceptance before chat',
        () async {
      final requestId = await requestLesson();
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();
      final data = request.data()!;
      expect(data['studentUid'], 'student');
      expect(data['studentName'], '실제 수강생');
      expect(data['instructorId'], 'coach');
      expect(data['instructorUid'], 'coach');
      expect(data['instructorName'], '승인된 코치');
      expect(data['sport'], '축구');
      expect(data['signatureMove'], '인사이드 패스');
      expect(data.containsKey('attendanceBadge'), isFalse);
      expect(data['participantIds'], ['coach', 'student']);
      expect(data['status'], 'pending');
      expect(data['paymentRequired'], isFalse);
      expect(data['isInstructorInitiated'], isFalse);
      expect(data['createdAt'], isNotNull);

      final room =
          await firestore.collection('chat_rooms').doc('coach_student').get();
      expect(room.exists, isFalse);
      expect((await firestore.collection('lesson_requests').get()).docs,
          hasLength(1));
    });

    test('a pending instructor cannot receive requests', () async {
      await firestore.collection('instructors').doc('coach').update({
        'status': 'pending',
      });

      await expectLater(requestLesson(), throwsStateError);

      await expectNoRequests();
    });

    test('a coach cannot request their own lesson', () async {
      await expectLater(
        requestsFor('coach').requestLesson(
          instructorId: 'coach',
          instructorName: '승인된 코치',
          coachUid: 'coach',
        ),
        throwsStateError,
      );

      await expectNoRequests();
    });

    test('another coach cannot apply as a student', () async {
      await expectLater(
        requestLesson(studentUid: 'other-coach'),
        throwsStateError,
      );

      await expectNoRequests();
    });

    test('an administrator can request a lesson for operational verification',
        () async {
      final requestId = await requestLesson(studentUid: 'admin');
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();

      expect(request.data()?['studentUid'], 'admin');
      expect(request.data()?['studentName'], '관리자');
      expect(request.data()?['status'], 'pending');
      expect(
          (await firestore
                  .collection('active_lesson_requests')
                  .doc('coach_admin')
                  .get())
              .exists,
          isTrue);
    });

    test('a signed out user cannot create a lesson request', () async {
      final service = LessonService(
        firestore: firestore,
        auth: MockFirebaseAuth(),
      );
      await expectLater(
        service.requestLesson(
          instructorId: 'coach',
          instructorName: '승인된 코치',
          coachUid: 'coach',
        ),
        throwsStateError,
      );

      await expectNoRequests();
    });

    test('missing or mismatched instructor identities create no records',
        () async {
      for (final coachUid in <String?>[null, '', 'other-coach']) {
        await expectLater(
          requestsFor('student').requestLesson(
            instructorId: 'coach',
            instructorName: '승인된 코치',
            coachUid: coachUid,
          ),
          throwsStateError,
        );
      }

      await expectNoRequests();
    });

    test('pending and accepted requests both prevent duplicate requests',
        () async {
      final requestId = await requestLesson();

      await expectLater(requestLesson(), throwsStateError);
      await matchingFor('coach').acceptLesson(requestId);
      await expectLater(requestLesson(), throwsStateError);

      final requests = await firestore.collection('lesson_requests').get();
      expect(requests.docs.map((doc) => doc.id), [requestId]);
      expect(requests.docs.single.data()['status'], 'accepted');
      final active = await firestore.collection('active_lesson_requests').get();
      expect(active.docs, hasLength(1));
      expect(active.docs.single.data()['requestId'], requestId);
      expect(
          (await firestore.collection('chat_rooms').get()).docs, hasLength(1));
    });
  });

  group('lesson transitions', () {
    test(
        'only the assigned coach can accept and retries keep one active lesson',
        () async {
      final requestId = await requestLesson();
      for (final uid in ['student', 'other-coach']) {
        await expectLater(
          matchingFor(uid).acceptLesson(requestId),
          throwsStateError,
        );
      }
      final requestRef = firestore.collection('lesson_requests').doc(requestId);
      expect((await requestRef.get()).data()!['status'], 'pending');

      await matchingFor('coach').acceptLesson(requestId);
      await matchingFor('coach').acceptLesson(requestId);

      expect((await requestRef.get()).data()!['status'], 'accepted');
      expect((await requestRef.get()).data()!.containsKey('attendanceBadge'),
          isFalse);
      expect((await studentData())['lessonCount'], 2);
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
      expect(
        (await firestore.collection('chat_rooms').doc('coach_student').get())
            .data(),
        {
          'participantIds': ['coach', 'student'],
          'studentUid': 'student',
          'studentName': '실제 수강생',
          'coachUid': 'coach',
          'coachName': '승인된 코치',
        },
      );
    });

    test('a pending request cannot be completed or award progress', () async {
      final requestId = await requestLesson();

      await expectLater(
        matchingFor('coach').completeLesson(
          requestId: requestId,
          reviewScore: 4,
        ),
        throwsStateError,
      );

      expect((await studentData())['lessonCount'], 2);
      expect((await studentData())['reviewScores'], [3.0]);
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();
      expect(request.data()!['status'], 'pending');
      expect(request.data()!.containsKey('attendanceBadge'), isFalse);
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
    });

    test('students and other coaches cannot complete an accepted lesson',
        () async {
      final requestId = await requestLesson();
      await matchingFor('coach').acceptLesson(requestId);

      for (final uid in ['student', 'other-coach']) {
        await expectLater(
          matchingFor(uid).completeLesson(requestId: requestId, reviewScore: 4),
          throwsStateError,
        );
      }

      expect((await studentData())['lessonCount'], 2);
      expect((await studentData())['reviewScores'], [3.0]);
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();
      expect(request.data()!['status'], 'accepted');
      expect(request.data()!.containsKey('attendanceBadge'), isFalse);
    });

    test('completion records progress and feedback exactly once', () async {
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await coach.completeLesson(
        requestId: requestId,
        reviewScore: 4,
        feedback: '  패스 정확도가 좋아졌어요.  ',
      );
      await coach.completeLesson(
        requestId: requestId,
        reviewScore: 5,
        feedback: 'Retry must not replace the committed review',
      );

      final student = await studentData();
      expect(student['lessonCount'], 3);
      expect(student['reviewScores'], [3.0, 4.0]);
      expect(student['teacherMatchCount'], 1);
      expect(student['name'], '실제 수강생');
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();
      expect(request.data()!['status'], 'completed');
      expect(request.data()!['reviewScore'], 4.0);
      expect(request.data()!['reviewFeedback'], '패스 정확도가 좋아졌어요.');
      expect(request.data()!['completedAt'], isNotNull);
      final badge = request.data()!['attendanceBadge'] as Map<String, dynamic>;
      expect(badge['instructorUid'], 'coach');
      expect(badge['instructorName'], '승인된 코치');
      expect(badge['signatureMove'], '인사이드 패스');
      expect(badge['sport'], '축구');
      expect(badge['verifiedBy'], 'coach');
      expect(badge['awardedAt'], isA<Timestamp>());
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          isEmpty);
    });

    test('separate completed lessons retain repeated equal review scores',
        () async {
      final requestIds = <String>[];
      final coach = matchingFor('coach');
      for (var i = 0; i < 2; i++) {
        final requestId = await requestLesson();
        requestIds.add(requestId);
        await coach.acceptLesson(requestId);
        await coach.completeLesson(requestId: requestId, reviewScore: 4);
        await coach.completeLesson(requestId: requestId, reviewScore: 4);
      }

      expect(requestIds.toSet(), hasLength(2));
      expect((await studentData())['lessonCount'], 4);
      expect((await studentData())['reviewScores'], [3.0, 4.0, 4.0]);
      expect((await studentData())['teacherMatchCount'], 1);
      final requests = await firestore.collection('lesson_requests').get();
      expect(requests.docs, hasLength(2));
      expect(requests.docs.map((doc) => doc.data()['status']),
          everyElement('completed'));
      final badges = await LessonBadgeService(
        firestore: firestore,
        auth: authFor('student'),
      ).earnedBadges().first;
      expect(badges.map((badge) => badge.id), unorderedEquals(requestIds));
      expect(
          badges.map((badge) => badge.signatureMove), everyElement('인사이드 패스'));
      expect(
          (await firestore.collection('chat_rooms').get()).docs, hasLength(1));
    });

    for (final status in ['cancelled', 'rejected']) {
      test('$status releases the active request and permits another lesson',
          () async {
        final requestId = await requestLesson();
        if (status == 'cancelled') {
          await matchingFor('student').cancelLesson(requestId);
          await matchingFor('student').cancelLesson(requestId);
        } else {
          await matchingFor('coach').rejectLesson(requestId);
          await matchingFor('coach').rejectLesson(requestId);
        }

        final previousRequest =
            await firestore.collection('lesson_requests').doc(requestId).get();
        expect(previousRequest.data()!['status'], status);
        expect(previousRequest.data()!.containsKey('attendanceBadge'), isFalse);
        expect(
            (await firestore.collection('active_lesson_requests').get()).docs,
            isEmpty);
        expect((await studentData())['lessonCount'], 2);

        final replacementId = await requestLesson();
        expect(replacementId, isNot(requestId));
        expect((await firestore.collection('lesson_requests').get()).docs,
            hasLength(2));
        final active =
            await firestore.collection('active_lesson_requests').get();
        expect(active.docs, hasLength(1));
        expect(active.docs.single.data()['requestId'], replacementId);
      });
    }

    test('unrelated users cannot cancel or reject another person\'s request',
        () async {
      final requestId = await requestLesson();
      await expectLater(
        matchingFor('other-student').cancelLesson(requestId),
        throwsStateError,
      );
      await expectLater(
        matchingFor('coach').cancelLesson(requestId),
        throwsStateError,
      );
      await expectLater(
        matchingFor('other-coach').rejectLesson(requestId),
        throwsStateError,
      );
      await expectLater(
        matchingFor('student').rejectLesson(requestId),
        throwsStateError,
      );
      final request =
          await firestore.collection('lesson_requests').doc(requestId).get();
      expect(request.data()!['status'], 'pending');
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
    });

    test('accepted lessons cannot be cancelled or rejected', () async {
      final requestId = await requestLesson();
      await matchingFor('coach').acceptLesson(requestId);

      await expectLater(
        matchingFor('student').cancelLesson(requestId),
        throwsStateError,
      );
      await expectLater(
        matchingFor('coach').rejectLesson(requestId),
        throwsStateError,
      );

      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
    });
  });

  group('attendance badge awards', () {
    test('opening the collection at any pre-completion stage awards nothing',
        () async {
      final badges = LessonBadgeService(
        firestore: firestore,
        auth: authFor('student'),
      );
      expect(await badges.earnedBadges().first, isEmpty);
      expect(await badges.earnedBadges().first, isEmpty);
      expect(
          (await firestore.collection('lesson_requests').get()).docs, isEmpty);
      final requestId = await requestLesson();
      expect(await badges.earnedBadges().first, isEmpty);
      await matchingFor('coach').acceptLesson(requestId);
      expect(await badges.earnedBadges().first, isEmpty);
      expect((await studentData())['lessonCount'], 2);
    });

    test('a completion retry preserves the awarded metadata and timestamp',
        () async {
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await coach.completeLesson(requestId: requestId, reviewScore: 4);
      final ref = firestore.collection('lesson_requests').doc(requestId);
      final before = (await ref.get()).data()!;
      await firestore.collection('instructors').doc('coach').update({
        'name': '변경된 이름',
        'sport': '테니스',
        'signatureMove': '새로운 기술',
      });

      await coach.completeLesson(
        requestId: requestId,
        reviewScore: 5,
        signatureMove: '재시도 기술',
      );

      expect((await ref.get()).data(), before);
      final profile =
          (await firestore.collection('instructors').doc('coach').get())
              .data()!;
      expect(profile['signatureMove'], '새로운 기술');
      final badges = await LessonBadgeService(
        firestore: firestore,
        auth: authFor('student'),
      ).earnedBadges().first;
      expect(badges, hasLength(1));
      expect(badges.single.instructorName, '승인된 코치');
      expect(badges.single.sport, '축구');
      expect(badges.single.signatureMove, '인사이드 패스');
    });

    test('lesson completion cannot replace the managed coach signature',
        () async {
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await expectLater(
          coach.completeLesson(
            requestId: requestId,
            reviewScore: 4,
            signatureMove: '  감아차기  ',
          ),
          throwsStateError);

      await coach.completeLesson(requestId: requestId, reviewScore: 4);

      final request =
          (await firestore.collection('lesson_requests').doc(requestId).get())
              .data()!;
      expect(request['attendanceBadge']['signatureMove'], '인사이드 패스');
      expect(
          (await firestore.collection('instructors').doc('coach').get())
              .data()!['signatureMove'],
          '인사이드 패스');
      final nextId = await requestLesson();
      expect(
        (await firestore.collection('lesson_requests').doc(nextId).get())
            .data()!['signatureMove'],
        '인사이드 패스',
      );
    });

    test('current instructor signature takes priority over request snapshot',
        () async {
      final requestId = await requestLesson();
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': '새로운 기술',
      });
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await coach.completeLesson(requestId: requestId, reviewScore: 4);

      final data =
          (await firestore.collection('lesson_requests').doc(requestId).get())
              .data()!;
      expect(data['signatureMove'], '인사이드 패스');
      expect(data['attendanceBadge']['signatureMove'], '새로운 기술');
    });

    test('legacy coach account signature is copied into requests and awards',
        () async {
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': FieldValue.delete(),
      });
      await firestore.collection('users').doc('coach').update({
        'signatureMove': '  발리슛  ',
      });
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await coach.completeLesson(requestId: requestId, reviewScore: 4);

      final data =
          (await firestore.collection('lesson_requests').doc(requestId).get())
              .data()!;
      expect(data['signatureMove'], '발리슛');
      expect(data['attendanceBadge']['signatureMove'], '발리슛');
    });

    test('request signature is a fallback when the instructor profile is gone',
        () async {
      final requestId = await requestLesson();
      await firestore.collection('instructors').doc('coach').delete();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await coach.completeLesson(requestId: requestId, reviewScore: 4);

      final data =
          (await firestore.collection('lesson_requests').doc(requestId).get())
              .data()!;
      expect(data['attendanceBadge']['signatureMove'], '인사이드 패스');
      expect(data['attendanceBadge']['sport'], '축구');
    });

    test('missing signature leaves accepted lesson and progress intact',
        () async {
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': '   ',
      });
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      final ref = firestore.collection('lesson_requests').doc(requestId);
      final before = (await ref.get()).data();

      await expectLater(
        coach.completeLesson(
          requestId: requestId,
          reviewScore: 4,
          signatureMove: '   ',
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('시그니처 기술'),
        )),
      );

      expect((await ref.get()).data(), before);
      expect((await studentData())['lessonCount'], 2);
      expect((await studentData())['reviewScores'], [3.0]);
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
      // Badge changes happen in profile management, not in the completion form.
      await expectLater(
          coach.completeLesson(
            requestId: requestId,
            reviewScore: 4,
            signatureMove: '라보나',
          ),
          throwsStateError);
      await firestore.collection('instructors').doc('coach').update({
        'signatureMove': '라보나',
      });
      await coach.completeLesson(requestId: requestId, reviewScore: 4);
      expect(
          (await ref.get()).data()!['attendanceBadge']['signatureMove'], '라보나');
    });

    test('overlong signature fails before changing any profiles or lesson',
        () async {
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      final ref = firestore.collection('lesson_requests').doc(requestId);
      final before = (await ref.get()).data();
      final instructorRef = firestore.collection('instructors').doc('coach');
      final instructorBefore = (await instructorRef.get()).data();
      final coachRef = firestore.collection('users').doc('coach');
      final coachBefore = (await coachRef.get()).data();

      await expectLater(
        coach.completeLesson(
          requestId: requestId,
          reviewScore: 4,
          signatureMove: '기' * 41,
        ),
        throwsStateError,
      );

      expect((await ref.get()).data(), before);
      expect((await instructorRef.get()).data(), instructorBefore);
      expect((await coachRef.get()).data(), coachBefore);
      expect((await studentData())['lessonCount'], 2);
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
    });

    test('missing student cannot partially update a signature or award a badge',
        () async {
      final requestId = await requestLesson();
      final coach = matchingFor('coach');
      await coach.acceptLesson(requestId);
      await firestore.collection('users').doc('student').delete();
      final ref = firestore.collection('lesson_requests').doc(requestId);
      final before = (await ref.get()).data();

      await expectLater(
        coach.completeLesson(
          requestId: requestId,
          reviewScore: 4,
          signatureMove: '새로운 기술',
        ),
        throwsStateError,
      );

      expect((await ref.get()).data(), before);
      expect(
        (await firestore.collection('instructors').doc('coach').get())
            .data()!['signatureMove'],
        '인사이드 패스',
      );
      expect((await firestore.collection('active_lesson_requests').get()).docs,
          hasLength(1));
    });
  });

  group('lesson visibility', () {
    test('each account sees only lessons it participates in', () async {
      final studentRequest = await requestLesson();
      final otherRequest = await requestLesson(studentUid: 'other-student');

      final studentLessons = await matchingFor('student').lessons().first;
      final otherLessons = await matchingFor('other-student').lessons().first;
      final coachLessons = await matchingFor('coach').lessons().first;
      final unrelatedLessons = await matchingFor('other-coach').lessons().first;

      expect(studentLessons.docs.map((doc) => doc.id), [studentRequest]);
      expect(otherLessons.docs.map((doc) => doc.id), [otherRequest]);
      expect(coachLessons.docs.map((doc) => doc.id),
          unorderedEquals([studentRequest, otherRequest]));
      expect(unrelatedLessons.docs, isEmpty);
    });

    test('instructor lists include only approved profiles for the chosen sport',
        () async {
      await firestore.collection('instructors').doc('pending').set({
        'sport': '축구',
        'status': 'pending',
      });
      await firestore.collection('instructors').doc('rejected').set({
        'sport': '축구',
        'status': 'rejected',
      });
      await firestore.collection('instructors').doc('tennis').set({
        'sport': '테니스',
        'status': 'approved',
      });
      final instructors = InstructorService(
        firestore: firestore,
        auth: authFor('student'),
      );

      final football = await instructors.approvedInstructors('축구').first;
      final tennis = await instructors.approvedInstructors('테니스').first;
      final lessonList =
          await requestsFor('student').getInstructors('축구').first;

      expect(football.docs.map((doc) => doc.id), ['coach']);
      expect(tennis.docs.map((doc) => doc.id), ['tennis']);
      expect(lessonList.docs.map((doc) => doc.id), ['coach']);
    });
  });

  group('review validation', () {
    for (final score in [1.0, 2.5, 5.0]) {
      test('accepts review score $score', () async {
        final requestId = await requestLesson();
        final coach = matchingFor('coach');
        await coach.acceptLesson(requestId);

        await coach.completeLesson(requestId: requestId, reviewScore: score);

        expect((await studentData())['lessonCount'], 3);
        expect((await studentData())['reviewScores'], [3.0, score]);
      });
    }

    for (final score in [
      -1.0,
      0.0,
      0.999,
      5.001,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('rejects invalid review score $score without recording progress',
          () async {
        final requestId = await requestLesson();
        final coach = matchingFor('coach');
        await coach.acceptLesson(requestId);

        await expectLater(
          coach.completeLesson(requestId: requestId, reviewScore: score),
          throwsArgumentError,
        );

        expect((await studentData())['lessonCount'], 2);
        expect((await studentData())['reviewScores'], [3.0]);
        final request =
            await firestore.collection('lesson_requests').doc(requestId).get();
        expect(request.data()!['status'], 'accepted');
        expect(
            (await firestore.collection('active_lesson_requests').get()).docs,
            hasLength(1));
      });
    }
  });
}
