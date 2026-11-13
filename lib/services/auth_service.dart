import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    bool? isWeb,
    Future<User?> Function()? googleSignInCallback,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn,
        _isWeb = isWeb ?? kIsWeb,
        _googleSignInCallback = googleSignInCallback;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  GoogleSignIn? _googleSignIn;
  final bool _isWeb;
  final Future<User?> Function()? _googleSignInCallback;

  User? get currentUser => _auth.currentUser;
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  Future<User?> signInWithGoogle() async {
    User? user;
    GoogleAuthProvider? webProvider;
    final googleSignInCallback = _googleSignInCallback;
    try {
      if (googleSignInCallback != null) {
        user = await googleSignInCallback();
      } else if (_isWeb) {
        // Start the popup directly from the button action so browsers allow it.
        webProvider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        user = (await _auth.signInWithPopup(webProvider)).user;
      } else {
        final google = _googleSignIn ??= GoogleSignIn();
        final account = await google.signIn();
        if (account == null) return null;
        final tokens = await account.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: tokens.accessToken,
          idToken: tokens.idToken,
        );
        user = (await _auth.signInWithCredential(credential)).user;
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request' ||
          error.code == 'web-context-canceled') {
        return null;
      }
      // Some mobile browsers block popups even when they start directly from
      // a button. Redirect sign-in is the supported fallback in that case.
      if (_isWeb &&
          googleSignInCallback == null &&
          error.code == 'popup-blocked' &&
          webProvider != null) {
        await _auth.signInWithRedirect(webProvider);
        return null;
      }
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) return null;
      rethrow;
    }

    if (user == null) return null;
    await _ensureProfile(user);
    return user;
  }

  /// Resolves Firebase's one-account-per-email conflict without creating a
  /// second ONEPOINT profile. The existing password account owns the data and
  /// receives Google as an additional sign-in method after reauthentication.
  Future<User?> linkGoogleToPasswordAccount({
    required FirebaseAuthException conflict,
    required String password,
  }) async {
    final email = conflict.email?.trim() ?? '';
    final pendingCredential = conflict.credential;
    if (conflict.code != 'account-exists-with-different-credential' ||
        email.isEmpty ||
        pendingCredential == null ||
        password.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: '기존 계정의 로그인 정보를 확인해 주세요.',
      );
    }

    final existing = (await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    ))
        .user;
    if (existing == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: '기존 계정을 찾을 수 없습니다.',
      );
    }
    _requireSameSession(existing.uid);

    try {
      final linked =
          (await existing.linkWithCredential(pendingCredential)).user;
      final user = linked ?? existing;
      _requireSameSession(user.uid);
      await _ensureProfile(user);
      return user;
    } catch (_) {
      // Do not leave a partially resolved password session behind if provider
      // linking itself failed.
      await _auth.signOut();
      rethrow;
    }
  }

  Future<void> _ensureProfile(User user) async {
    _requireSameSession(user.uid);
    final reference = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      _requireSameSession(user.uid);
      // Signing in must never overwrite an existing profile or its awards.
      if (snapshot.exists) return;
      transaction.set(reference, {
        'uid': user.uid,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'profileImage': user.photoURL ?? '',
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
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<bool> needsProfileCompletion() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    _requireSameSession(user.uid);
    if ((snapshot.data()?['accountStatus'] ?? 'active') != 'active') {
      throw FirebaseAuthException(
          code: 'user-disabled', message: '정지 또는 삭제된 계정입니다.');
    }
    // Only an explicit completion flag permits entry into the app.
    return !snapshot.exists || snapshot.data()?['profileCompleted'] != true;
  }

  /// Returns the unfinished signup type so an interrupted coach signup can
  /// resume at the approval application instead of asking for the role again.
  Future<String?> incompleteRequestedRole() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    _requireSameSession(user.uid);
    final data = snapshot.data();
    if (data == null || data['profileCompleted'] == true) return null;
    return data['requestedRole'] == 'coach' ? 'coach' : null;
  }

  Stream<String> accountStatus(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data()?['accountStatus'] as String? ?? 'active');

  Future<void> signOut() async {
    await _auth.signOut();
    if (!_isWeb) {
      // Logout can be invoked by a new service instance after app restoration.
      final google = _googleSignIn ??= GoogleSignIn();
      await google.signOut();
    }
  }

  void _requireSameSession(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('로그인 상태가 변경되었습니다. 다시 로그인해 주세요.');
    }
  }
}
