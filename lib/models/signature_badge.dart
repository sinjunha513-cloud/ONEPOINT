import 'package:cloud_firestore/cloud_firestore.dart';

const signatureBadgeNameMaxLength = 20;

final _signatureBadgeNamePattern = RegExp(
  r'^[가-힣ㄱ-ㅎㅏ-ㅣA-Za-z0-9]{1,20}$',
);

String normalizeSignatureBadgeName(String value) => value.trim().toLowerCase();

String? signatureBadgeNameError(String value) {
  final name = value.trim();
  if (name.isEmpty) return '시그니처 기술을 입력해 주세요.';
  if (name.length > signatureBadgeNameMaxLength) {
    return '시그니처 기술은 $signatureBadgeNameMaxLength자 이내로 입력해 주세요.';
  }
  if (!_signatureBadgeNamePattern.hasMatch(name)) {
    return '공백 없이 한 단어로 입력해 주세요. (한글·영문·숫자)';
  }
  return null;
}

class SignatureBadge {
  const SignatureBadge({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.colorIndex,
    required this.sequence,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String name;
  final String normalizedName;
  final int colorIndex;
  final int sequence;
  final String createdBy;
  final DateTime? createdAt;

  factory SignatureBadge.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    return SignatureBadge(
      id: document.id,
      name: data['name'] as String? ?? document.id,
      normalizedName: data['normalizedName'] as String? ?? document.id,
      colorIndex: (data['colorIndex'] as num?)?.toInt() ?? 0,
      sequence: (data['sequence'] as num?)?.toInt() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

class SignatureBadgeCreationResult {
  const SignatureBadgeCreationResult(this.badge, {required this.created});

  final SignatureBadge badge;
  final bool created;
}
