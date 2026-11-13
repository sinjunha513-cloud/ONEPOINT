import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/models/lesson_badge.dart';
import 'package:onepoint_lesson/services/lesson_badge_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  LessonBadgeService serviceFor(String uid) => LessonBadgeService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: uid),
          signedIn: true,
        ),
      );

  Map<String, dynamic> lesson({
    String studentUid = 'student',
    String status = 'completed',
    DateTime? awardedAt,
    String signatureMove = '인사이드 패스',
  }) =>
      {
        'studentUid': studentUid,
        'status': status,
        'attendanceBadge': {
          'instructorUid': 'coach',
          'instructorName': '담당 코치',
          'signatureMove': signatureMove,
          'sport': '축구',
          'verifiedBy': 'coach',
          'awardedAt': awardedAt == null ? null : Timestamp.fromDate(awardedAt),
        },
      };

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  test('only completed explicit awards belonging to the current student appear',
      () async {
    final requests = firestore.collection('lesson_requests');
    await requests.doc('earned').set(lesson());
    await requests.doc('other-student').set(lesson(studentUid: 'other'));
    for (final status in ['pending', 'accepted', 'rejected', 'cancelled']) {
      await requests.doc(status).set(lesson(status: status));
    }
    await requests.doc('legacy').set({
      'studentUid': 'student',
      'status': 'completed',
      'signatureMove': '레거시 기술',
    });
    await requests.doc('invalid-award').set(lesson(signatureMove: '   '));
    await requests.doc('invalid-shape').set({
      'studentUid': 'student',
      'status': 'completed',
      'attendanceBadge': 'invalid',
    });

    final badges = await serviceFor('student').earnedBadges().first;

    expect(badges.map((badge) => badge.id), ['earned']);
    expect(badges.single.requestId, 'earned');
    expect(badges.single.instructorUid, 'coach');
    expect(badges.single.instructorName, '담당 코치');
    expect(badges.single.signatureMove, '인사이드 패스');
    expect(badges.single.verifiedBy, 'coach');
    expect(badges.single.sport, '축구');
    expect(await serviceFor('coach').earnedBadges().first, isEmpty);
    expect((await serviceFor('other').earnedBadges().first).single.id,
        'other-student');
  });

  test('sorts newest awards first with stable IDs for ties and missing dates',
      () async {
    final requests = firestore.collection('lesson_requests');
    final old = DateTime.utc(2026, 9, 1);
    final latest = DateTime.utc(2026, 9, 29);
    await requests.doc('old').set(lesson(awardedAt: old));
    await requests.doc('latest-z').set(lesson(awardedAt: latest));
    await requests.doc('undated-z').set(lesson());
    await requests.doc('latest-a').set(lesson(awardedAt: latest));
    await requests.doc('undated-a').set(lesson());

    final badges = await serviceFor('student').earnedBadges().first;

    expect(badges.map((badge) => badge.id), [
      'latest-a',
      'latest-z',
      'old',
      'undated-a',
      'undated-z',
    ]);
    expect(badges.first.awardedAt?.toUtc(), latest);
    expect(badges.last.awardedAt, isNull);
  });

  test('signed out collection reads are empty and perform no writes', () async {
    final service = LessonBadgeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
    );
    expect(await service.earnedBadges().first, isEmpty);
    expect(await service.earnedBadges().first, isEmpty);
    expect((await firestore.collection('lesson_requests').get()).docs, isEmpty);
    expect((await firestore.collection('users').get()).docs, isEmpty);
  });

  test(
      'reading historical completed lessons never creates retrospective awards',
      () async {
    final ref = firestore.collection('lesson_requests').doc('historical');
    final historical = {
      'studentUid': 'student',
      'status': 'completed',
      'signatureMove': '과거 기술',
    };
    await ref.set(historical);

    for (var visit = 0; visit < 3; visit++) {
      expect(await serviceFor('student').earnedBadges().first, isEmpty);
    }

    expect((await ref.get()).data(), historical);
    expect((await firestore.collection('lesson_requests').get()).docs,
        hasLength(1));
  });

  test('the collection stream receives awards when a lesson is completed',
      () async {
    final ref = firestore.collection('lesson_requests').doc('lesson');
    await ref.set({
      'studentUid': 'student',
      'status': 'accepted',
    });
    final firstAward = serviceFor('student')
        .earnedBadges()
        .firstWhere((badges) => badges.isNotEmpty);

    await ref.update(lesson(awardedAt: DateTime.utc(2026, 9, 29)));

    expect((await firstAward).single.id, 'lesson');
  });

  test(
      'the parser tolerates unresolved timestamps and ignores malformed badges',
      () {
    expect(LessonBadge.fromLesson('id', lesson())?.awardedAt, isNull);
    for (final invalid in <Object?>[
      null,
      false,
      [],
      {'signatureMove': '패스'}
    ]) {
      expect(
        LessonBadge.fromLesson('id', {
          'status': 'completed',
          'attendanceBadge': invalid,
        }),
        isNull,
      );
    }
  });
}
