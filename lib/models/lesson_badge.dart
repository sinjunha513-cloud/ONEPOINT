import 'package:cloud_firestore/cloud_firestore.dart';

/// A signature move earned by attending one completed lesson.
///
/// The lesson ID is the badge ID, so repeat lessons earn separate badges while
/// retrying completion of the same lesson cannot create another badge.
class LessonBadge {
  const LessonBadge({
    required this.id,
    required this.instructorUid,
    required this.instructorName,
    required this.signatureMove,
    required this.sport,
    this.signatureBadgeId,
    this.signatureBadgeColorIndex,
    this.awardedAt,
    this.verifiedBy = '',
  });

  final String id;
  String get requestId => id;
  final String instructorUid;
  final String instructorName;
  final String signatureMove;
  final String sport;
  final String? signatureBadgeId;
  final int? signatureBadgeColorIndex;
  final DateTime? awardedAt;
  final String verifiedBy;

  /// Historical lessons without an explicit award never become badges merely
  /// because the student opens their collection.
  static LessonBadge? fromLesson(String requestId, Map<String, dynamic> data) {
    if (data['status'] != 'completed') return null;
    final award = data['attendanceBadge'];
    if (award is! Map) return null;
    final instructorUid = _text(award['instructorUid']);
    final instructorName = _text(award['instructorName']);
    final signatureMove = _text(award['signatureMove']);
    if (instructorUid.isEmpty ||
        instructorName.isEmpty ||
        signatureMove.isEmpty) {
      return null;
    }
    final awardedAt = award['awardedAt'];
    return LessonBadge(
      id: requestId,
      instructorUid: instructorUid,
      instructorName: instructorName,
      signatureMove: signatureMove,
      sport: _text(award['sport']),
      signatureBadgeId: _nullableText(award['signatureBadgeId']),
      signatureBadgeColorIndex:
          (award['signatureBadgeColorIndex'] as num?)?.toInt(),
      awardedAt: awardedAt is Timestamp ? awardedAt.toDate() : null,
      verifiedBy: _text(award['verifiedBy']),
    );
  }

  static String _text(dynamic value) => value is String ? value.trim() : '';
  static String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }
}
