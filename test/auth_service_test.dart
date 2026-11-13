import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:onepoint_lesson/services/auth_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockUser user;
  late MockFirebaseAuth auth;

  AuthService service({Future<User?> Function()? signIn, bool isWeb = true}) =>
      AuthService(
        auth: auth,
        firestore: db,
        isWeb: isWeb,
        googleSignInCallback: signIn,
      );

  setUp(() {
    db = FakeFirebaseFirestore();
    user = MockUser(
      uid: 'google-user',
      email: 'member@example.com',
      displayName: 'Google Name',
      photoURL: 'https://example.com/avatar.png',
    );
    auth = MockFirebaseAuth(mockUser: user);
  });

  test('web Google sign-in creates an incomplete student profile', () async {
    final subject = service();
    expect(await subject.signInWithGoogle(), user);
    expect(subject.currentUser?.uid, user.uid);
    final data = (await db.collection('users').doc(user.uid).get()).data()!;
    expect(data, {
      'uid': 'google-user',
      'email': 'member@example.com',
      'name': 'Google Name',
      'profileImage': 'https://example.com/avatar.png',
      'role': 'student',
      'requestedRole': 'student',
      'targetTier': '비기너',
      'aspirations': '',
      'videoUrl': '',
      'lessonCount': 0,
      'reviewScores': <double>[],
      'teacherMatchCount': 0,
      'feedLikeCount': 0,
      'profileCompleted': false,
      'createdAt': isA<Timestamp>(),
      'updatedAt': isA<Timestamp>(),
    });
    expect(await subject.needsProfileCompletion(), isTrue);
    expect((await db.collection('lessonBadges').get()).docs, isEmpty);
  });

  test('repeated Google login preserves every existing profile field',
      () async {
    final before = {
      'role': 'coach',
      'requestedRole': 'coach',
      'name': 'Chosen name',
      'email': 'saved@example.com',
      'profileImage': 'https://example.com/chosen.png',
      'targetTier': '프로',
      'aspirations': 'Saved goal',
      'videoUrl': 'https://example.com/video',
      'lessonCount': 8,
      'reviewScores': [4.5, 5.0],
      'teacherMatchCount': 3,
      'feedLikeCount': 12,
      'settings': {'notifications': false},
      'signatureMove': 'Coach skill',
      'profileCompleted': true,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(12345),
    };
    await db.collection('users').doc(user.uid).set(before);
    final subject = service();
    await subject.signInWithGoogle();
    await subject.signInWithGoogle();
    expect((await db.collection('users').doc(user.uid).get()).data(), before);
    expect(await subject.needsProfileCompletion(), isFalse);
  });

  test('legacy users retain their fields and must complete registration',
      () async {
    final before = {
      'role': 'admin',
      'name': 'Legacy member',
      'lessonCount': 20
    };
    await db.collection('users').doc(user.uid).set(before);
    final subject = service();
    await subject.signInWithGoogle();
    expect(await subject.needsProfileCompletion(), isTrue);
    expect((await db.collection('users').doc(user.uid).get()).data(), before);
  });

  test('missing optional Google profile values use empty defaults', () async {
    auth.mockUser = MockUser(uid: 'empty-profile', photoURL: '');
    await service().signInWithGoogle();
    final data =
        (await db.collection('users').doc('empty-profile').get()).data()!;
    expect(data['name'], '');
    expect(data['email'], '');
    expect(data['profileImage'], '');
  });

  test('cancelled Google account selection creates no profile', () async {
    final subject = service(signIn: () async => null);
    expect(await subject.signInWithGoogle(), isNull);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  for (final code in [
    'popup-closed-by-user',
    'cancelled-popup-request',
    'web-context-canceled',
  ]) {
    test('Google cancellation $code is handled quietly', () async {
      final subject = service(
        signIn: () async => throw FirebaseAuthException(code: code),
      );
      expect(await subject.signInWithGoogle(), isNull);
      expect((await db.collection('users').get()).docs, isEmpty);
    });
  }

  test('native Google cancellation is handled quietly', () async {
    final subject = service(
      isWeb: false,
      signIn: () async =>
          throw PlatformException(code: GoogleSignIn.kSignInCanceledError),
    );
    expect(await subject.signInWithGoogle(), isNull);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  for (final code in [
    'popup-blocked',
    'operation-not-allowed',
    'network-request-failed',
    'account-exists-with-different-credential',
  ]) {
    test('Google authentication failure $code remains visible', () async {
      final error = FirebaseAuthException(code: code);
      final subject = service(signIn: () async => throw error);
      await expectLater(subject.signInWithGoogle(), throwsA(same(error)));
      expect((await db.collection('users').get()).docs, isEmpty);
    });
  }

  test('native configuration errors are not treated as cancellation', () async {
    final error = PlatformException(code: 'sign_in_failed');
    final subject = service(isWeb: false, signIn: () async => throw error);
    await expectLater(subject.signInWithGoogle(), throwsA(same(error)));
  });

  test('Google result without matching Firebase session cannot create profile',
      () async {
    final subject = service(signIn: () async => user);
    await expectLater(subject.signInWithGoogle(), throwsStateError);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  test('Google result for another signed-in account cannot create profile',
      () async {
    await auth.signInWithCredential(null);
    final subject = service(signIn: () async => MockUser(uid: 'other-user'));
    await expectLater(subject.signInWithGoogle(), throwsStateError);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  test('signed-in account without a profile needs registration', () async {
    await auth.signInWithCredential(null);
    expect(await service().needsProfileCompletion(), isTrue);
  });

  test('signed-out profile checks fail instead of routing to home', () async {
    await expectLater(service().needsProfileCompletion(), throwsStateError);
  });

  test('email login returns the authenticated user without awarding activity',
      () async {
    final subject = service();
    expect(
      await subject.signInWithEmailAndPassword(
        email: ' member@example.com ',
        password: 'password',
      ),
      user,
    );
    expect(subject.currentUser?.uid, user.uid);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  test('password reauthentication links a pending Google credential', () async {
    final subject = service();
    final conflict = FirebaseAuthException(
      code: 'account-exists-with-different-credential',
      email: 'member@example.com',
      credential: GoogleAuthProvider.credential(idToken: 'pending-id-token'),
    );
    final linked = await subject.linkGoogleToPasswordAccount(
      conflict: conflict,
      password: 'existing-password',
    );
    expect(linked?.uid, user.uid);
    expect((await db.collection('users').doc(user.uid).get()).exists, isTrue);
  });

  test('sign-out clears Firebase authentication', () async {
    final subject = service();
    await subject.signInWithGoogle();
    await subject.signOut();
    expect(subject.currentUser, isNull);
  });

  test('web sign-in opens Google account selection', () async {
    final recordingAuth = _RecordingAuth(user);
    final subject =
        AuthService(auth: recordingAuth, firestore: db, isWeb: true);
    await subject.signInWithGoogle();
    expect(recordingAuth.provider, isA<GoogleAuthProvider>());
    expect((recordingAuth.provider as GoogleAuthProvider).parameters,
        {'prompt': 'select_account'});
    expect(recordingAuth.credential, isNull);
  });

  test('native sign-in exchanges Google tokens then signs out both sessions',
      () async {
    final recordingAuth = _RecordingAuth(user);
    final google = _FakeGoogleSignIn(_FakeGoogleAccount());
    final subject = AuthService(
      auth: recordingAuth,
      firestore: db,
      googleSignIn: google,
      isWeb: false,
    );
    expect(await subject.signInWithGoogle(), user);
    expect(recordingAuth.credential?.providerId, 'google.com');
    expect((recordingAuth.credential as OAuthCredential).accessToken, 'access');
    expect((recordingAuth.credential as OAuthCredential).idToken, 'id-token');
    expect(recordingAuth.provider, isNull);
    await subject.signOut();
    expect(subject.currentUser, isNull);
    expect(google.signedOut, isTrue);
  });

  test('native account selection cancellation never authenticates Firebase',
      () async {
    final subject = AuthService(
      auth: auth,
      firestore: db,
      googleSignIn: _FakeGoogleSignIn(null),
      isWeb: false,
    );
    expect(await subject.signInWithGoogle(), isNull);
    expect(subject.currentUser, isNull);
    expect((await db.collection('users').get()).docs, isEmpty);
  });
}

class _RecordingAuth extends MockFirebaseAuth {
  _RecordingAuth(MockUser user) : super(mockUser: user);

  AuthProvider? provider;
  AuthCredential? credential;

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) {
    this.provider = provider;
    return super.signInWithPopup(provider);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    this.credential = credential;
    return super.signInWithCredential(credential);
  }
}

class _FakeGoogleSignIn implements GoogleSignIn {
  _FakeGoogleSignIn(this.account);

  final GoogleSignInAccount? account;
  bool signedOut = false;

  @override
  Future<GoogleSignInAccount?> signIn() async => account;

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signedOut = true;
    return account;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleAccount implements GoogleSignInAccount {
  @override
  Future<GoogleSignInAuthentication> get authentication async => _FakeTokens();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTokens implements GoogleSignInAuthentication {
  @override
  String? get accessToken => 'access';

  @override
  String? get idToken => 'id-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
