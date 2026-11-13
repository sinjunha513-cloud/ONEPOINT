import 'package:onepoint_lesson/models/signup_consent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/auth_service.dart';
import 'package:onepoint_lesson/services/instructor_service.dart';
import 'package:onepoint_lesson/services/user_profile_service.dart';

class _FailingFirestore extends FakeFirebaseFirestore {
  int transactionCalls = 0;
  int? failAtTransaction;
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) {
    transactionCalls++;
    if (transactionCalls == failAtTransaction) {
      return Future.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    }
    return super
        .runTransaction(handler, timeout: timeout, maxAttempts: maxAttempts);
  }
}

void main() {
  late _FailingFirestore db;
  late MockFirebaseAuth auth;
  late UserProfileService profiles;
  late AuthService session;
  const draft = UserProfileDraft(name: '회원');
  Future<int> members() async => (await db
          .collection('users')
          .where('profileCompleted', isEqualTo: true)
          .get())
      .docs
      .length;

  setUp(() {
    db = _FailingFirestore();
    auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'member', email: 'member@example.com'),
        signedIn: true);
    profiles = UserProfileService(auth: auth, firestore: db);
    session = AuthService(auth: auth, firestore: db, isWeb: true);
  });

  test('1 account initialization and interruption do not add a member',
      () async {
    await profiles.initializeAccount(expectedUid: 'member');
    expect(
        (await db.collection('users').doc('member').get())
            .data()!['profileCompleted'],
        false);
    expect(await members(), 0);
  });
  test('2 completing signup adds exactly one member even after a retry',
      () async {
    for (var i = 0; i < 2; i++) {
      await profiles.completeProfile(
          consent:
              const SignupConsent(termsAccepted: true, privacyAccepted: true),
          profile: draft,
          requestedRole: 'student',
          expectedUid: 'member');
    }
    expect(await members(), 1);
    expect((await db.collection('users').get()).docs.length, 1);
  });
  test('3 an incomplete restored session requires onboarding', () async {
    await profiles.initializeAccount(expectedUid: 'member');
    expect(await session.needsProfileCompletion(), true);
  });
  test('4 completed session can enter home', () async {
    await profiles.completeProfile(
        consent:
            const SignupConsent(termsAccepted: true, privacyAccepted: true),
        profile: draft,
        requestedRole: 'student',
        expectedUid: 'member');
    expect(await session.needsProfileCompletion(), false);
  });
  test(
      '5 coach completes only after required application; approval stays pending',
      () async {
    await profiles.completeProfile(
        consent:
            const SignupConsent(termsAccepted: true, privacyAccepted: true),
        profile: draft,
        requestedRole: 'coach',
        expectedUid: 'member');
    expect(await members(), 0);
    await db.collection('signature_badges').doc('감아차기').set({
      'name': '감아차기',
      'normalizedName': '감아차기',
      'colorIndex': 7,
      'sequence': 0,
      'createdBy': 'member',
      'createdAt': DateTime(2026),
    });
    await InstructorService(auth: auth, firestore: db).registerInstructor(
        name: '코치',
        sport: '축구',
        career: '지도 경력',
        rating: '0.0',
        signatureMove: '감아차기',
        signatureBadgeId: '감아차기',
        signatureBadgeColorIndex: 7);
    expect(await members(), 1);
    expect(
        (await db.collection('instructors').doc('member').get())
            .data()!['status'],
        'pending');
    expect((await db.collection('users').doc('member').get()).data()!['role'],
        'student');
  });
  test('6 failed Firestore completion leaves account incomplete and uncounted',
      () async {
    await profiles.initializeAccount(expectedUid: 'member');
    // Allow initialization to read the existing account, then reject the
    // transaction that would save the final profile and completion flag.
    db.failAtTransaction = db.transactionCalls + 2;
    await expectLater(
        profiles.completeProfile(
            consent:
                const SignupConsent(termsAccepted: true, privacyAccepted: true),
            profile: draft,
            requestedRole: 'student',
            expectedUid: 'member'),
        throwsA(isA<FirebaseException>()));
    expect(await members(), 0);
    expect(
        (await db.collection('users').doc('member').get())
            .data()!['profileCompleted'],
        false);
  });
  test(
      '7 missing completion field never grants membership or changes legacy data',
      () async {
    final before = {'name': '기존 회원', 'role': 'student'};
    await db.collection('users').doc('member').set(before);
    expect(await session.needsProfileCompletion(), true);
    expect(await members(), 0);
    expect((await db.collection('users').doc('member').get()).data(), before);
  });
  test('invalid role cannot finish onboarding', () async {
    await expectLater(
        profiles.completeProfile(
            consent:
                const SignupConsent(termsAccepted: true, privacyAccepted: true),
            profile: draft,
            requestedRole: 'admin',
            expectedUid: 'member'),
        throwsArgumentError);
    expect(await members(), 0);
  });
  test('required consents cannot be bypassed through the service', () async {
    await profiles.initializeAccount(expectedUid: 'member');
    await expectLater(
        profiles.completeProfile(
            profile: draft, requestedRole: 'student', expectedUid: 'member'),
        throwsStateError);
    await expectLater(
        profiles.completeProfile(
            profile: draft,
            requestedRole: 'student',
            expectedUid: 'member',
            consent: const SignupConsent(termsAccepted: true)),
        throwsStateError);
    expect(await members(), 0);
  });
}
