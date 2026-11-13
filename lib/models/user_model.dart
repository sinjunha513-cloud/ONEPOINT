enum UserRole { student, coach, admin }

class UserModel {
  final String uid;
  final String email;
  final String name;
  final UserRole role; // student: 수강생, coach: 코치
  final String? profileImage;
  final String? currentTier; // 현재 티어 (수강생)
  final String? targetTier; // 목표 티어 / 지도 가능 목표 티어
  final String? playStyle; // 주요 / 선호 플레이스타일
  final String? signatureMove; // 시그니처 기술 / 배우고 싶은 기술
  final List<String> tags; // 태그
  final String? aspiration; // 포부 및 한마디
  final String? videoUrl; // 대표 플레이 / 코칭 영상 URL
  final String? bio; // 약력 및 자기소개

  // 코치 전용
  final int? studentCount; // 누적 수강생 수
  final double? rating; // 코치 평점

  // 승급/점수제 전용 데이터
  final int lessonCount; // 레슨 완료 횟수
  final List<double> reviewScores; // 받은 코치 리뷰 점수 목록
  final int teacherMatchCount; // 코치가 먼저 매칭을 제안한 횟수
  final int feedLikeCount; // 피드에서 받은 총 좋아요 수

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.profileImage,
    this.currentTier,
    this.targetTier,
    this.playStyle,
    this.signatureMove,
    this.tags = const [],
    this.aspiration,
    this.videoUrl,
    this.bio,
    this.studentCount,
    this.rating,
    this.lessonCount = 0,
    this.reviewScores = const [],
    this.teacherMatchCount = 0,
    this.feedLikeCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role.name,
      'profileImage': profileImage,
      'currentTier': currentTier,
      'targetTier': targetTier,
      'playStyle': playStyle,
      'signatureMove': signatureMove,
      'tags': tags,
      'aspiration': aspiration,
      'videoUrl': videoUrl,
      'bio': bio,
      'studentCount': studentCount,
      'rating': rating,
      'lessonCount': lessonCount,
      'reviewScores': reviewScores,
      'teacherMatchCount': teacherMatchCount,
      'feedLikeCount': feedLikeCount,
    };
  }
}
