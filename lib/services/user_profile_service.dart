import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/signup_consent.dart';
import '../config/sports.dart';

/// The editable fields shared by registration and profile settings.
class UserProfileDraft {
  const UserProfileDraft({
    required this.name,
    this.profileImage = '',
    this.targetTier = '비기너',
    this.aspirations = '',
    this.videoUrl = '',
  });

  factory UserProfileDraft.fromMap(Map<String, dynamic> data) {
    return UserProfileDraft(
      name: data['name'] as String? ?? '',
      profileImage:
          data['profileImage'] as String? ?? data['photoUrl'] as String? ?? '',
      targetTier: data['targetTier'] as String? ?? '비기너',
      aspirations:
          data['aspirations'] as String? ?? data['bio'] as String? ?? '',
      videoUrl: data['videoUrl'] as String? ?? '',
    );
  }

  final String name;
  final String profileImage;
  final String targetTier;
  final String aspirations;
  final String videoUrl;

  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        'profileImage': profileImage.trim(),
        'targetTier': targetTier,
        'aspirations': aspirations.trim(),
        'videoUrl': videoUrl.trim(),
      };
}

class UserProfileService {
  UserProfileService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  String? _pendingSignupUserId;

  Future<void> saveProfile(UserProfileDraft profile,
      {required String expectedUid}) async {
    final user = _requireUser(expectedUid);
    _validate(profile);
    // Update only editable values. Membership, progress and awards stay intact.
    await _firestore.collection('users').doc(user.uid).update({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _requireUser(expectedUid);
  }

  Future<void> createAccount({
    required String email,
    required String password,
    required String requestedRole,
    required UserProfileDraft profile,
    SignupConsent consent = const SignupConsent(),
  }) async {
    _validate(profile);
    _validateConsent(consent);
    var user = _auth.currentUser;
    // Retry a failed profile write using the account created by this service.
    if (user == null ||
        user.uid != _pendingSignupUserId ||
        user.email?.toLowerCase() != email.trim().toLowerCase()) {
      user = (await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ))
          .user;
      _pendingSignupUserId = user?.uid;
    }
    if (user == null) throw StateError('회원 계정을 만들 수 없습니다.');
    await initializeAccount(expectedUid: user.uid);
    await completeProfile(
        profile: profile,
        requestedRole: requestedRole,
        expectedUid: user.uid,
        consent: consent);
    _pendingSignupUserId = null;
  }

  Future<void> initializeAccount({required String expectedUid}) async {
    final user = _requireUser(expectedUid);
    final reference = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      _requireUser(expectedUid);
      if (snapshot.exists) return;
      transaction.set(reference, {
        'uid': user.uid,
        'email': user.email ?? '',
        'name': '',
        'role': 'student',
        'lessonCount': 0,
        'reviewScores': <double>[],
        'teacherMatchCount': 0,
        'feedLikeCount': 0,
        'profileCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> completeProfile({
    required UserProfileDraft profile,
    required String requestedRole,
    required String expectedUid,
    SignupConsent consent = const SignupConsent(),
  }) async {
    final user = _requireUser(expectedUid);
    _validate(profile);
    _validateConsent(consent);
    if (!['student', 'coach'].contains(requestedRole)) {
      throw ArgumentError('가입 유형을 선택해 주세요.');
    }
    await initializeAccount(expectedUid: expectedUid);
    final reference = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final instructor = requestedRole == 'coach'
          ? await transaction
              .get(_firestore.collection('instructors').doc(user.uid))
          : null;
      final pdfId = instructor?.data()?['careerPdfId'];
      final pdf = pdfId is String
          ? await transaction.get(_firestore
              .collection('coach_document_uploads')
              .doc(user.uid)
              .collection('files')
              .doc(pdfId))
          : null;
      // Authentication can change in another tab while the read is pending.
      _requireUser(expectedUid);
      final values = <String, dynamic>{
        if (!snapshot.exists) ...{
          // Coach privileges still require the existing approval workflow.
          'role': 'student',
          'uid': user.uid,
          'lessonCount': 0,
          'reviewScores': <double>[],
          'teacherMatchCount': 0,
          'feedLikeCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        },
        ...profile.toMap(),
        ...consent.toMap(),
        'email': user.email ?? '',
        'requestedRole': requestedRole == 'coach' ? 'coach' : 'student',
        'profileCompleted': snapshot.data()?['profileCompleted'] == true ||
            requestedRole == 'student' ||
            (instructor?.data()?['name'] is String &&
                (instructor!.data()!['name'] as String).trim().isNotEmpty &&
                supportedSports.contains(instructor.data()?['sport']) &&
                instructor.data()?['career'] is String &&
                ((instructor.data()!['career'] as String).trim().isNotEmpty ||
                    pdf?.data()?['verified'] == true) &&
                instructor.data()?['signatureMove'] is String &&
                (instructor.data()!['signatureMove'] as String)
                    .trim()
                    .isNotEmpty),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (snapshot.exists) {
        transaction.update(reference, values);
      } else {
        transaction.set(reference, values);
      }
    });
    _requireUser(expectedUid);
  }

  User _requireUser(String expectedUid) {
    final user = _auth.currentUser;
    if (user == null) throw StateError('로그인이 필요합니다.');
    if (user.uid != expectedUid) {
      throw StateError('로그인 계정이 변경되었습니다. 프로필 화면을 다시 열어 주세요.');
    }
    return user;
  }

  void _validate(UserProfileDraft profile) {
    if (profile.name.trim().isEmpty) {
      throw ArgumentError('이름 / 닉네임을 입력해 주세요.');
    }
  }

  void _validateConsent(SignupConsent consent) {
    if (!consent.isAccepted) {
      throw StateError('이용약관과 개인정보 수집·이용에 동의해 주세요.');
    }
  }
}
