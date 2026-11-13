import 'package:onepoint_lesson/models/signup_consent.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/user_profile_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late UserProfileService profiles;

  const draft = UserProfileDraft(
    name: '  새 이름  ',
    profileImage: 'data:image/png;base64,cGhvdG8=',
    targetTier: '프로 2',
    aspirations: '  다음 레슨이 기대돼요  ',
    videoUrl: '  https://example.com/practice  ',
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'member', email: 'member@example.com'),
      signedIn: true,
    );
    profiles = UserProfileService(auth: auth, firestore: db);
  });

  test('editing updates all profile fields and preserves membership and badges',
      () async {
    final member = db.collection('users').doc('member');
    await member.set({
      'name': '이전 이름',
      'role': 'coach',
      'requestedRole': 'coach',
      'email': 'member@example.com',
      'lessonCount': 12,
      'reviewScores': [4.0, 5.0],
      'teacherMatchCount': 3,
      'feedLikeCount': 8,
      'signatureMove': '라 크로케타',
      'profileCompleted': true,
    });
    await member
        .collection('lessonBadges')
        .doc('lesson-1')
        .set({'signatureMove': '감아차기'});
    await profiles.saveProfile(draft, expectedUid: 'member');
    final data = (await member.get()).data()!;
    for (final entry in draft.toMap().entries) {
      expect(data[entry.key], entry.value);
    }
    expect(data['role'], 'coach');
    expect(data['requestedRole'], 'coach');
    expect(data['email'], 'member@example.com');
    expect(data['lessonCount'], 12);
    expect(data['reviewScores'], [4.0, 5.0]);
    expect(data['teacherMatchCount'], 3);
    expect(data['feedLikeCount'], 8);
    expect(data['signatureMove'], '라 크로케타');
    expect(
        (await member.collection('lessonBadges').doc('lesson-1').get()).exists,
        isTrue);
  });

  test(
      'Google profile completion uses signed in account and initializes student membership',
      () async {
    await profiles.completeProfile(
        consent:
            const SignupConsent(termsAccepted: true, privacyAccepted: true),
        profile: draft,
        requestedRole: 'coach',
        expectedUid: 'member');
    expect(auth.currentUser!.uid, 'member');
    final data = (await db.collection('users').doc('member').get()).data()!;
    expect(data['profileCompleted'], isFalse);
    expect(data['email'], 'member@example.com');
    expect(data['requestedRole'], 'coach');
    expect(data['role'], 'student');
    expect(data['lessonCount'], 0);
    expect(data['reviewScores'], isEmpty);
    expect(data['createdAt'], isNotNull);
    expect(data['videoUrl'], 'https://example.com/practice');
  });

  test('completing a partial or existing profile preserves progress and role',
      () async {
    final member = db.collection('users').doc('member');
    await member.set({
      'role': 'admin',
      'lessonCount': 18,
      'teacherMatchCount': 2,
      'reviewScores': [5.0],
      'feedLikeCount': 10,
      'signatureMove': '드래그백',
      'profileCompleted': false,
    });
    await profiles.completeProfile(
        consent:
            const SignupConsent(termsAccepted: true, privacyAccepted: true),
        profile: draft,
        requestedRole: 'student',
        expectedUid: 'member');
    final data = (await member.get()).data()!;
    expect(data['profileCompleted'], isTrue);
    expect(data['role'], 'admin');
    expect(data['lessonCount'], 18);
    expect(data['teacherMatchCount'], 2);
    expect(data['reviewScores'], [5.0]);
    expect(data['feedLikeCount'], 10);
    expect(data['signatureMove'], '드래그백');
  });

  test('legacy profile aliases migrate into canonical editable fields', () {
    final legacy = UserProfileDraft.fromMap({
      'name': '기존 사용자',
      'photoUrl': 'data:image/png;base64,cGhvdG8=',
      'bio': '기존 소개',
      'videoUrl': 'https://example.com/video',
    });
    expect(legacy.profileImage, 'data:image/png;base64,cGhvdG8=');
    expect(legacy.aspirations, '기존 소개');
    expect(legacy.videoUrl, 'https://example.com/video');
    expect(legacy.targetTier, '비기너');
    expect(
        UserProfileDraft.fromMap({
          'name': '사용자',
          'profileImage': '',
          'photoUrl': 'old',
          'aspirations': '',
          'bio': 'old'
        }).toMap()['profileImage'],
        '');
  });

  test('invalid edits do not modify saved profile', () async {
    final member = db.collection('users').doc('member');
    await member.set({'name': '기존 이름', 'lessonCount': 3});
    await expectLater(
        profiles.saveProfile(const UserProfileDraft(name: '  '),
            expectedUid: 'member'),
        throwsArgumentError);
    expect((await member.get()).data(), {'name': '기존 이름', 'lessonCount': 3});
  });

  test('profile completion requires authentication', () async {
    await auth.signOut();
    await expectLater(
        profiles.completeProfile(
            consent:
                const SignupConsent(termsAccepted: true, privacyAccepted: true),
            profile: draft,
            requestedRole: 'student',
            expectedUid: 'member'),
        throwsStateError);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  test('stale profile edit and onboarding cannot modify either account',
      () async {
    final member = db.collection('users').doc('member');
    final other = db.collection('users').doc('other');
    const before = {'name': '원래 사용자', 'lessonCount': 3};
    const otherBefore = {'name': '다른 사용자', 'lessonCount': 7};
    await member.set(before);
    await other.set(otherBefore);
    auth.mockUser = MockUser(uid: 'other', email: 'other@example.com');

    await expectLater(
        profiles.saveProfile(draft, expectedUid: 'member'), throwsStateError);
    await expectLater(
        profiles.completeProfile(
            consent:
                const SignupConsent(termsAccepted: true, privacyAccepted: true),
            profile: draft,
            requestedRole: 'coach',
            expectedUid: 'member'),
        throwsStateError);
    expect((await member.get()).data(), before);
    expect((await other.get()).data(), otherBefore);
  });

  test('switching accounts during completion read prevents its transaction',
      () async {
    final member = db.collection('users').doc('member');
    final other = db.collection('users').doc('other');
    const before = {'name': '원래 사용자', 'profileCompleted': false};
    const otherBefore = {'name': '다른 사용자', 'profileCompleted': false};
    await member.set(before);
    await other.set(otherBefore);

    final completion = profiles.completeProfile(
        consent:
            const SignupConsent(termsAccepted: true, privacyAccepted: true),
        profile: draft,
        requestedRole: 'coach',
        expectedUid: 'member');
    // The transaction has started, but its document read has not resolved yet.
    auth.mockUser = MockUser(uid: 'other', email: 'other@example.com');
    await expectLater(completion, throwsStateError);
    expect((await member.get()).data(), before);
    expect((await other.get()).data(), otherBefore);
  });
}
