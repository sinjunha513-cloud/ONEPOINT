import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/instructor_service.dart';
import 'package:onepoint_lesson/models/signature_badge.dart';

void main() {
  late FakeFirebaseFirestore db;

  InstructorService serviceFor(String uid) => InstructorService(
        firestore: db,
        auth: MockFirebaseAuth(mockUser: MockUser(uid: uid), signedIn: true),
      );

  Future<void> seedBadge(String name, {int colorIndex = 7}) async {
    final id = normalizeSignatureBadgeName(name);
    await db.collection('signature_badges').doc(id).set({
      'name': name.trim(),
      'normalizedName': id,
      'colorIndex': colorIndex,
      'sequence': 0,
      'createdBy': 'applicant',
      'createdAt': DateTime(2026),
    });
  }

  Future<void> submit(InstructorService service,
      {String? signatureMove}) async {
    final name = signatureMove?.trim();
    if (name != null && signatureBadgeNameError(name) == null) {
      await seedBadge(name);
    }
    await service.registerInstructor(
      name: '테스트 코치',
      sport: '축구',
      career: '지도 경력 3년',
      rating: '5.0',
      signatureMove: signatureMove,
      signatureBadgeId: name == null ? null : normalizeSignatureBadgeName(name),
      signatureBadgeColorIndex: name == null ? null : 7,
    );
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('applicant').set({'role': 'student'});
    await db.collection('users').doc('admin').set({'role': 'admin'});
  });

  test('application stays private and does not grant coach permission',
      () async {
    final service = serviceFor('applicant');
    await submit(service);
    final data =
        (await db.collection('instructors').doc('applicant').get()).data()!;
    expect(data['uid'], 'applicant');
    expect(data['userId'], 'applicant');
    expect(data['status'], 'pending');
    expect(data['lessonLevel'], '초급 환영');
    expect(data['rating'], '0.0');
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'student');
    expect((await service.approvedInstructors('축구').first).docs, isEmpty);
  });

  test('admin approval publishes the correct sport and grants coach role',
      () async {
    await submit(serviceFor('applicant'));
    final admin = serviceFor('admin');
    await admin.approveInstructor('applicant');
    // FakeFirestore does not execute Functions projection triggers.
    // The real allowlisted projection is exercised in the Emulator suite.
    await db.collection('public_instructors').doc('applicant').set({
      'sport': '축구',
      'status': 'approved',
      'name': 'Public coach',
    });
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'coach');
    expect((await admin.approvedInstructors('축구').first).docs.single.id,
        'applicant');
    expect((await admin.approvedInstructors('테니스').first).docs, isEmpty);
    await expectLater(admin.approveInstructor('applicant'), throwsStateError);
  });

  test('application stores trimmed signature skill for lesson badges',
      () async {
    await submit(serviceFor('applicant'), signatureMove: '  라크로케타  ');
    final data =
        (await db.collection('instructors').doc('applicant').get()).data()!;
    expect(data['signatureMove'], '라크로케타');
    expect(data['signatureBadgeId'], '라크로케타');
    expect(data['signatureBadgeColorIndex'], 7);
    expect(data['status'], 'pending');
  });

  test('resubmission preserves omitted signature and accepts a new signature',
      () async {
    final applicant = serviceFor('applicant');
    await submit(applicant, signatureMove: '감아차기');
    await db.collection('users').doc('applicant').update({
      'signatureMove': '이전 기술',
    });
    await submit(applicant);
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['signatureMove'],
        '감아차기');

    await submit(applicant, signatureMove: '  라크로케타  ');
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['signatureMove'],
        '라크로케타');
  });

  test('legacy user signature is used when instructor signature is missing',
      () async {
    await seedBadge('감아차기');
    await db.collection('users').doc('applicant').update({
      'signatureMove': '감아차기',
      'signatureBadgeId': '감아차기',
      'signatureBadgeColorIndex': 7,
    });
    await submit(serviceFor('applicant'));
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['signatureMove'],
        '감아차기');
  });

  test('invalid signature is rejected before changing an application',
      () async {
    final applicant = serviceFor('applicant');
    await submit(applicant, signatureMove: '감아차기');
    for (final invalidSignature in [
      '',
      '   ',
      '두 단어',
      List.filled(21, '가').join()
    ]) {
      await expectLater(submit(applicant, signatureMove: invalidSignature),
          throwsArgumentError);
    }
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['signatureMove'],
        '감아차기');
  });

  test('non-admin approval and rejection do not modify pending application',
      () async {
    final applicant = serviceFor('applicant');
    await submit(applicant);
    await expectLater(
        applicant.approveInstructor('applicant'), throwsStateError);
    await expectLater(
        applicant.rejectInstructor('applicant'), throwsStateError);
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['status'],
        'pending');
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'student');
  });

  test('mismatched account identity cannot receive approval', () async {
    await submit(serviceFor('applicant'));
    await db
        .collection('instructors')
        .doc('applicant')
        .update({'uid': 'someone_else'});
    await expectLater(
        serviceFor('admin').approveInstructor('applicant'), throwsStateError);
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'student');
  });

  test('approved profile edits require new approval and preserve earned rating',
      () async {
    final applicant = serviceFor('applicant');
    await submit(applicant);
    await serviceFor('admin').approveInstructor('applicant');
    await db
        .collection('instructors')
        .doc('applicant')
        .update({'rating': '4.5'});
    await submit(applicant);
    final data =
        (await db.collection('instructors').doc('applicant').get()).data()!;
    expect(data['status'], 'pending');
    expect(data['rating'], '4.5');
    expect(data.containsKey('approvedAt'), isFalse);
    expect((await applicant.approvedInstructors('축구').first).docs, isEmpty);
  });

  test('rejected applicants can correct and resubmit their profile', () async {
    final applicant = serviceFor('applicant');
    await submit(applicant);
    await serviceFor('admin').rejectInstructor('applicant');
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['status'],
        'rejected');
    await submit(applicant);
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['status'],
        'pending');
  });

  test(
      'only admins freely assign roles while their own admin access is protected',
      () async {
    final admin = serviceFor('admin');
    await submit(serviceFor('applicant'));
    await admin.updateUserRole('applicant', 'coach');
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'coach');
    expect(
        (await db.collection('instructors').doc('applicant').get())
            .data()!['status'],
        'pending');
    await admin.updateUserRole('applicant', 'admin');
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'admin');
    await admin.updateUserRole('applicant', 'student');
    await expectLater(
        admin.updateUserRole('admin', 'student'), throwsStateError);
    await expectLater(
        serviceFor('applicant').updateUserRole('applicant', 'admin'),
        throwsStateError);
  });

  test('removing coach permission removes their public profile', () async {
    final admin = serviceFor('admin');
    await submit(serviceFor('applicant'));
    await admin.approveInstructor('applicant');
    await admin.updateUserRole('applicant', 'student');
    expect((await admin.approvedInstructors('축구').first).docs, isEmpty);
    expect(
        (await db.collection('users').doc('applicant').get()).data()!['role'],
        'student');
  });

  test('signed-out visitors cannot submit an instructor application', () async {
    final service = InstructorService(firestore: db, auth: MockFirebaseAuth());
    await expectLater(submit(service), throwsStateError);
    expect((await db.collection('instructors').get()).docs, isEmpty);
  });
}
