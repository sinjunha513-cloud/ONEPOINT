import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/signup_consent.dart';
import '../config/sports.dart';
import '../models/signature_badge.dart';
import '../utils/ttl_memory_cache.dart';

class _InstructorCacheKey {
  const _InstructorCacheKey(this.firestore, this.sport);

  final FirebaseFirestore firestore;
  final String sport;

  @override
  bool operator ==(Object other) =>
      other is _InstructorCacheKey &&
      identical(other.firestore, firestore) &&
      other.sport == sport;

  @override
  int get hashCode => Object.hash(identityHashCode(firestore), sport);
}

class InstructorService {
  InstructorService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static final _approvedInstructorCache =
      TtlMemoryCache<_InstructorCacheKey, QuerySnapshot<Map<String, dynamic>>>(
    timeToLive: const Duration(minutes: 2),
    maxEntries: 20,
  );

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return uid;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> approvedInstructors(
      String sport) async* {
    final key = _InstructorCacheKey(_db, sport);
    final cached = _approvedInstructorCache.getIfFresh(key);
    if (cached != null) yield cached;

    // Keep Firestore's live listener as the source of truth. The memory cache
    // only supplies an immediate first frame when this screen is opened again.
    await for (final snapshot in _db
        .collection('public_instructors')
        .where('sport', isEqualTo: sport)
        .where('status', isEqualTo: 'approved')
        .snapshots()) {
      _approvedInstructorCache.put(key, snapshot);
      yield snapshot;
    }
  }

  static void clearPublicCache() => _approvedInstructorCache.clear();

  Future<void> registerInstructor({
    required String name,
    required String sport,
    required String career,
    required String rating,
    String lessonLevel = '초급 환영',
    String? signatureMove,
    String? signatureBadgeId,
    int? signatureBadgeColorIndex,
    String? careerPdfId,
  }) async {
    if (name.trim().isEmpty ||
        (career.trim().isEmpty &&
            (careerPdfId == null || careerPdfId.isEmpty))) {
      throw ArgumentError('이름과 경력을 입력해 주세요.');
    }
    if (!supportedSports.contains(sport)) {
      throw ArgumentError('종목을 확인해 주세요.');
    }
    if (!coachWelcomeLevels.contains(lessonLevel)) {
      throw ArgumentError('수업 난이도를 선택해 주세요.');
    }
    final trimmedSignature = signatureMove?.trim();
    if (trimmedSignature != null) {
      final error = signatureBadgeNameError(trimmedSignature);
      if (error != null) throw ArgumentError(error);
      if (signatureBadgeId == null || signatureBadgeColorIndex == null) {
        throw ArgumentError('전역 목록에서 시그니처 뱃지를 선택해 주세요.');
      }
    }
    final uid = _uid;
    final profileRef = _db.collection('users').doc(uid);
    final instructorRef = _db.collection('instructors').doc(uid);
    await _db.runTransaction((transaction) async {
      final profile = await transaction.get(profileRef);
      final instructor = await transaction.get(instructorRef);
      final pdf = careerPdfId == null
          ? null
          : await transaction.get(_db
              .collection('coach_document_uploads')
              .doc(uid)
              .collection('files')
              .doc(careerPdfId));
      if (careerPdfId != null && pdf?.data()?['verified'] != true) {
        throw StateError('경력 PDF 검증을 완료해 주세요.');
      }
      if (!profile.exists ||
          !['student', 'coach'].contains(profile.data()?['role'])) {
        throw StateError('수강생 또는 코치 계정에서 신청할 수 있습니다.');
      }
      if (_uid != uid) throw StateError('로그인 계정이 변경되었습니다.');
      final profileSignature = profile.data()?['signatureMove'];
      final existingSignature = instructor.data()?['signatureMove'];
      final fallbackSignature = instructor.data()?['signatureMove'] == null &&
              profileSignature is String &&
              signatureBadgeNameError(profileSignature.trim()) == null
          ? profileSignature.trim()
          : null;
      final signatureToSave = trimmedSignature ??
          (existingSignature is String &&
                  signatureBadgeNameError(existingSignature.trim()) == null
              ? existingSignature.trim()
              : fallbackSignature);
      final badgeIdToSave = signatureBadgeId ??
          (instructor.data()?['signatureBadgeId'] as String?) ??
          (profile.data()?['signatureBadgeId'] as String?);
      final badgeColorToSave = signatureBadgeColorIndex ??
          (instructor.data()?['signatureBadgeColorIndex'] as num?)?.toInt() ??
          (profile.data()?['signatureBadgeColorIndex'] as num?)?.toInt();
      DocumentSnapshot<Map<String, dynamic>>? selectedBadge;
      if (signatureToSave != null && badgeIdToSave != null) {
        selectedBadge = await transaction
            .get(_db.collection('signature_badges').doc(badgeIdToSave));
      }
      if (signatureToSave != null &&
          (badgeIdToSave == null ||
              badgeColorToSave == null ||
              selectedBadge?.data()?['name'] != signatureToSave ||
              (selectedBadge?.data()?['colorIndex'] as num?)?.toInt() !=
                  badgeColorToSave)) {
        throw StateError('선택한 시그니처 뱃지를 전역 목록에서 다시 확인해 주세요.');
      }
      final updates = <String, dynamic>{
        'uid': uid,
        'userId': uid,
        'name': name.trim(),
        'sport': sport,
        'lessonLevel': lessonLevel,
        'career': career.trim(),
        if (careerPdfId != null) 'careerPdfId': careerPdfId,
        if (signatureToSave != null) 'signatureMove': signatureToSave,
        if (badgeIdToSave != null) 'signatureBadgeId': badgeIdToSave,
        if (badgeColorToSave != null)
          'signatureBadgeColorIndex': badgeColorToSave,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // A coach finishes signup when the required application and profile
      // are committed together; approval remains instructors.status.
      final profileData = profile.data()!;
      if (profileData['profileCompleted'] != true &&
          profileData['requestedRole'] == 'coach') {
        if (profileData['name'] is! String ||
            (profileData['name'] as String).trim().isEmpty ||
            profileData['termsAccepted'] != true ||
            profileData['privacyAccepted'] != true ||
            profileData['consentVersion'] != SignupConsent.version ||
            signatureToSave == null ||
            signatureToSave.isEmpty) {
          throw StateError('필수 프로필과 시그니처 기술을 입력해 주세요.');
        }
        transaction.update(profileRef, {
          'profileCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (instructor.exists) {
        // 평점과 시그니처 등 이번 제출에 없는 기존 정보는 유지합니다.
        transaction.update(instructorRef, {
          ...updates,
          if (careerPdfId == null) 'careerPdfId': FieldValue.delete(),
          'approvedAt': FieldValue.delete(),
          'reviewedAt': FieldValue.delete(),
          'reviewedBy': FieldValue.delete(),
        });
      } else {
        transaction.set(instructorRef, {
          ...updates,
          'rating': '0.0',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    clearPublicCache();
  }

  Future<void> approveInstructor(String instructorId) =>
      _reviewInstructor(instructorId, approve: true);

  Future<void> rejectInstructor(String instructorId) =>
      _reviewInstructor(instructorId, approve: false);

  Future<void> _reviewInstructor(String instructorId,
      {required bool approve}) async {
    final adminUid = _uid;
    final instructorRef = _db.collection('instructors').doc(instructorId);
    final userRef = _db.collection('users').doc(instructorId);
    await _db.runTransaction((transaction) async {
      final admin =
          await transaction.get(_db.collection('users').doc(adminUid));
      final instructor = await transaction.get(instructorRef);
      final user = await transaction.get(userRef);
      if (admin.data()?['role'] != 'admin') {
        throw StateError('관리자만 코치 신청을 처리할 수 있습니다.');
      }
      final data = instructor.data();
      if (data == null || data['status'] != 'pending') {
        throw StateError('이미 처리되었거나 존재하지 않는 신청입니다.');
      }
      if (data['uid'] != instructorId || data['userId'] != instructorId) {
        throw StateError('신청자의 계정 정보가 일치하지 않습니다.');
      }
      if (!user.exists ||
          !['student', 'coach'].contains(user.data()?['role'])) {
        throw StateError('신청자의 계정 상태를 확인해 주세요.');
      }
      transaction.update(instructorRef, {
        'status': approve ? 'approved' : 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (approve) 'approvedAt': FieldValue.serverTimestamp(),
      });
      if (approve) {
        transaction.update(userRef, {
          'role': 'coach',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    clearPublicCache();
  }

  Future<void> updateUserRole(String userId, String role) async {
    if (!['student', 'coach', 'admin'].contains(role)) {
      throw ArgumentError('지원하지 않는 역할입니다.');
    }
    final adminUid = _uid;
    if (userId == adminUid && role != 'admin') {
      throw StateError('자신의 관리자 권한은 변경할 수 없습니다.');
    }
    final userRef = _db.collection('users').doc(userId);
    final instructorRef = _db.collection('instructors').doc(userId);
    await _db.runTransaction((transaction) async {
      final admin =
          await transaction.get(_db.collection('users').doc(adminUid));
      final user = await transaction.get(userRef);
      final instructor = await transaction.get(instructorRef);
      if (admin.data()?['role'] != 'admin') {
        throw StateError('관리자만 회원 권한을 변경할 수 있습니다.');
      }
      if (_uid != adminUid) throw StateError('로그인 계정이 변경되었습니다.');
      if (!user.exists) throw StateError('존재하지 않는 회원입니다.');
      // Admins may assign any role. Publishing an instructor profile remains
      // a separate approval action and does not happen as a side effect here.
      transaction.update(userRef, {
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (role != 'coach' && instructor.exists) {
        transaction.update(instructorRef, {
          'status': 'rejected',
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedBy': adminUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    clearPublicCache();
  }
}
