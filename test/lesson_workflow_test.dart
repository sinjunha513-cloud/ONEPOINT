import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/lesson_service.dart';
import 'package:onepoint_lesson/services/matching_service.dart';
import 'package:onepoint_lesson/services/chat_service.dart';
import 'support/fake_functions.dart';

// Server-side booking/completion invariants moved to security-tests/rules.test.mjs.
void main() {
  late FakeFirebaseFirestore db;
  MockFirebaseAuth auth(String uid) =>
      MockFirebaseAuth(mockUser: MockUser(uid: uid), signedIn: true);
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('student').set({'role': 'student'});
    await db.collection('users').doc('coach').set({'role': 'coach'});
    await db.collection('lesson_requests').doc('lesson').set({
      'studentUid': 'student',
      'instructorUid': 'coach',
      'studentName': 'Student',
      'instructorName': 'Coach',
      'participantIds': ['coach', 'student'],
      'status': 'pending',
      'paymentRequired': false
    });
    await db
        .collection('active_lesson_requests')
        .doc('coach_student')
        .set({'requestId': 'lesson'});
  });
  test(
      'booking delegates identity/price validation to server without private coach reads',
      () async {
    final calls = <String>[];
    final service = LessonService(
        firestore: db,
        auth: auth('student'),
        functions: FakeFunctions((name, data) async {
          calls.add(name);
          expect(
              data,
              name == 'requestLesson'
                  ? {'instructorId': 'coach'}
                  : {'instructorId': 'coach', 'slotId': 'slot'});
          return {'lessonId': 'server-created'};
        }));
    expect(
        await service.requestLesson(
            instructorId: 'coach',
            instructorName: 'Untrusted',
            coachUid: 'coach'),
        'server-created');
    expect(
        await service.requestLesson(
            instructorId: 'coach',
            instructorName: 'Untrusted',
            coachUid: 'coach',
            slotId: 'slot'),
        'server-created');
    expect(calls, ['requestLesson', 'requestLessonWithSlot']);
    expect((await db.collection('lesson_requests').get()).docs, hasLength(1));
  });
  test('self and mismatched coach identifiers are rejected before transport',
      () async {
    final service = LessonService(firestore: db, auth: auth('student'));
    for (final uid in ['student', null, 'other']) {
      await expectLater(
          service.requestLesson(
              instructorId: uid == 'student' ? 'student' : 'coach',
              instructorName: '',
              coachUid: uid),
          throwsStateError);
    }
  });
  test(
      'assigned coach accepts atomically with a chat room; retry preserves summary',
      () async {
    final coach = MatchingService(firestore: db, auth: auth('coach'));
    for (final uid in ['student', 'other']) {
      await expectLater(
          MatchingService(firestore: db, auth: auth(uid))
              .acceptLesson('lesson'),
          throwsStateError);
    }
    await coach.acceptLesson('lesson');
    final room = db.collection('chat_rooms').doc('coach_student');
    await room.update({'lastMessage': 'hello', 'lastMessageId': 'msg'});
    await coach.acceptLesson('lesson');
    expect((await room.get()).data()!['lastMessage'], 'hello');
    expect(
        (await db.collection('lesson_requests').doc('lesson').get())
            .data()!['status'],
        'accepted');
  });
  for (final status in ['cancelled', 'rejected']) {
    test('$status releases the active request without awarding progress',
        () async {
      final service = MatchingService(
          firestore: db,
          auth: auth(status == 'cancelled' ? 'student' : 'coach'));
      if (status == 'cancelled') {
        await service.cancelLesson('lesson');
      } else {
        await service.rejectLesson('lesson');
      }
      expect(
          (await db
                  .collection('active_lesson_requests')
                  .doc('coach_student')
                  .get())
              .exists,
          isFalse);
      expect(
          (await db.collection('lesson_requests').doc('lesson').get())
              .data()!['status'],
          status);
      expect(
          (await db.collection('users').doc('student').get())
              .data()!
              .containsKey('lessonCount'),
          isFalse);
    });
  }
  test(
      'completion calls trusted backend and propagates errors without local awards',
      () async {
    final service = MatchingService(
        firestore: db,
        auth: auth('coach'),
        functions: FakeFunctions((name, data) async {
          expect(name, 'completeLesson');
          expect(data, {
            'lessonId': 'lesson',
            'reviewScore': 4.0,
            'feedback': 'good',
            'signatureMove': 'kick'
          });
          throw FirebaseFunctionsException(
              code: 'failed-precondition', message: 'pending');
        }));
    await expectLater(
        service.completeLesson(
            requestId: 'lesson',
            reviewScore: 4,
            feedback: ' good ',
            signatureMove: 'kick'),
        throwsA(isA<FirebaseFunctionsException>()));
    expect(
        (await db.collection('lesson_requests').doc('lesson').get())
            .data()!['status'],
        'pending');
  });
  for (final score in [
    -1.0,
    0.0,
    0.999,
    5.001,
    double.nan,
    double.infinity,
    double.negativeInfinity
  ]) {
    test('invalid score $score fails before transport', () async {
      await expectLater(
          MatchingService(firestore: db, auth: auth('coach'))
              .completeLesson(requestId: 'lesson', reviewScore: score),
          throwsArgumentError);
    });
  }
  test('lesson streams contain only current participant', () async {
    await db.collection('lesson_requests').doc('other').set({
      'participantIds': ['other', 'coach'],
      'status': 'pending'
    });
    expect(
        (await MatchingService(firestore: db, auth: auth('student'))
                .lessons()
                .first)
            .docs
            .map((d) => d.id),
        ['lesson']);
  });
  test('public discovery ignores private applications and filters sport/status',
      () async {
    await db.collection('instructors').doc('private').set({
      'sport': 'football',
      'status': 'approved',
      'email': 'private@example.test'
    });
    await db
        .collection('public_instructors')
        .doc('published')
        .set({'sport': 'football', 'status': 'approved', 'name': 'Coach'});
    final service = LessonService(firestore: db, auth: auth('student'));
    expect(
        (await service.getInstructors('football').first).docs.map((d) => d.id),
        ['published']);
  });
  test(
      'signature lookup uses current own profile then supplied legacy fallback',
      () async {
    final service = MatchingService(firestore: db, auth: auth('coach'));
    expect(await service.currentSignatureMove(fallback: ' legacy '), 'legacy');
    await db
        .collection('instructors')
        .doc('coach')
        .set({'signatureMove': 'current'});
    expect(await service.currentSignatureMove(fallback: 'legacy'), 'current');
  });
  test('chat summary references the exact atomic message id', () async {
    await MatchingService(firestore: db, auth: auth('coach'))
        .acceptLesson('lesson');
    await ChatService(firestore: db, auth: auth('student'))
        .sendMessage('coach_student', ' hello ');
    final room = db.collection('chat_rooms').doc('coach_student');
    final data = (await room.get()).data()!;
    final message = (await room
            .collection('messages')
            .doc(data['lastMessageId'] as String)
            .get())
        .data()!;
    expect(data['lastMessage'], 'hello');
    expect(message['text'], data['lastMessage']);
    expect(message['senderId'], 'student');
  });
}
