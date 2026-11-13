import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/signature_badge_palette.dart';
import '../models/signature_badge.dart';

class SignatureBadgeService {
  SignatureBadgeService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return uid;
  }

  Stream<List<SignatureBadge>> watchCatalog() => _db
      .collection('signature_badges')
      .orderBy('sequence')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(SignatureBadge.fromDocument)
          .toList(growable: false));

  Stream<String?> watchCurrentSelection() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _db
        .collection('instructors')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.data()?['signatureBadgeId'] as String?);
  }

  Future<SignatureBadgeCreationResult> createOrGet(String rawName) async {
    final validation = signatureBadgeNameError(rawName);
    if (validation != null) throw ArgumentError(validation);
    final uid = _uid;
    final name = rawName.trim();
    final normalizedName = normalizeSignatureBadgeName(name);
    final badgeRef = _db.collection('signature_badges').doc(normalizedName);
    final metaRef = _db.collection('signature_badge_meta').doc('catalog');

    return _db.runTransaction((transaction) async {
      final existing = await transaction.get(badgeRef);
      if (existing.exists) {
        return SignatureBadgeCreationResult(
          SignatureBadge.fromDocument(existing),
          created: false,
        );
      }
      final account = await transaction.get(_db.collection('users').doc(uid));
      if (!account.exists ||
          !['student', 'coach'].contains(account.data()?['role'])) {
        throw StateError('코치 등록 계정에서 시그니처 뱃지를 만들 수 있습니다.');
      }
      final meta = await transaction.get(metaRef);
      final sequence = (meta.data()?['nextSequence'] as num?)?.toInt() ?? 0;
      final colorIndex = signatureBadgeColorIndexForSequence(sequence);
      final badge = SignatureBadge(
        id: normalizedName,
        name: name,
        normalizedName: normalizedName,
        colorIndex: colorIndex,
        sequence: sequence,
        createdBy: uid,
      );

      transaction.set(badgeRef, {
        'name': name,
        'normalizedName': normalizedName,
        'colorIndex': colorIndex,
        'sequence': sequence,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(
          metaRef,
          {
            'nextSequence': sequence + 1,
            'lastBadgeId': normalizedName,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return SignatureBadgeCreationResult(badge, created: true);
    });
  }

  Future<void> selectForCurrentCoach(SignatureBadge badge) async {
    final uid = _uid;
    final badgeRef = _db.collection('signature_badges').doc(badge.id);
    final instructorRef = _db.collection('instructors').doc(uid);
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((transaction) async {
      final storedBadge = await transaction.get(badgeRef);
      final instructor = await transaction.get(instructorRef);
      final user = await transaction.get(userRef);
      final stored = storedBadge.data();
      if (stored == null ||
          stored['name'] != badge.name ||
          stored['colorIndex'] != badge.colorIndex) {
        throw StateError('선택한 뱃지 정보를 다시 확인해 주세요.');
      }
      if (user.data()?['role'] != 'coach' ||
          instructor.data()?['status'] != 'approved') {
        throw StateError('승인된 코치만 마이페이지에서 뱃지를 변경할 수 있습니다.');
      }
      final selection = <String, dynamic>{
        'signatureMove': badge.name,
        'signatureBadgeId': badge.id,
        'signatureBadgeColorIndex': badge.colorIndex,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.update(instructorRef, selection);
      transaction.update(userRef, selection);
    });
  }
}
