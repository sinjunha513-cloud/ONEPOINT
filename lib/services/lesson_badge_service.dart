import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lesson_badge.dart';

class LessonBadgeService {
  LessonBadgeService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Reading the collection never grants attendance or changes lesson records.
  Stream<List<LessonBadge>> earnedBadges() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <LessonBadge>[]);
    // A single equality avoids requiring a new composite Firestore index.
    return _db
        .collection('lesson_requests')
        .where('studentUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final badges = snapshot.docs
          .map((doc) => LessonBadge.fromLesson(doc.id, doc.data()))
          .whereType<LessonBadge>()
          .toList();
      badges.sort((a, b) {
        final aDate = a.awardedAt;
        final bDate = b.awardedAt;
        if (aDate == null && bDate != null) return 1;
        if (aDate != null && bDate == null) return -1;
        final dateOrder = aDate == null ? 0 : bDate!.compareTo(aDate);
        return dateOrder == 0 ? a.id.compareTo(b.id) : dateOrder;
      });
      return badges;
    });
  }
}
