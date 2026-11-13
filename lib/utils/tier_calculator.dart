class TierProgressInfo {
  final String tierName;
  final int totalExp;
  final int currentTierExp;
  final double progressRatio;
  final bool isGeneralMember;

  TierProgressInfo({
    required this.tierName,
    required this.totalExp,
    required this.currentTierExp,
    required this.progressRatio,
    required this.isGeneralMember,
  });
}

class TierCalculator {
  static const List<String> tierList = [
    '비기너',
    '아마추어 3',
    '아마추어 2',
    '아마추어 1',
    '세미프로 3',
    '세미프로 2',
    '세미프로 1',
    '프로 3',
    '프로 2',
    '프로 1',
    '챌린저',
  ];

  static TierProgressInfo calculateTierInfo({
    required int lessonCount,
    required List<double> reviewScores,
    required int teacherMatchCount,
    required int feedLikeCount,
  }) {
    // 💡 1. 비율 기반(비례) 점수 산정 로직 적용
    // [레슨 빈도] 3회당 20점 -> 1회당 약 6.66점
    double lessonExp = lessonCount * (20.0 / 3.0);

    // [코치 평점] 5점 만점 기준 50점 -> 1점당 10점
    double reviewExp = 0;
    for (double score in reviewScores) {
      reviewExp += (score * 10.0);
    }

    // [코치 매칭 요청] 1회당 10점
    double matchExp = teacherMatchCount * 10.0;

    // [피드 좋아요] 1개당 1점
    double likeExp = feedLikeCount * 1.0;

    // 총합 계산 (소수점 버림 처리로 정수 EXP 계산)
    int totalExp = (lessonExp + reviewExp + matchExp + likeExp).toInt();

    // 2. 100점당 1티어 승급 계산
    int tierIndex = totalExp ~/ 100;
    int currentTierExp = totalExp % 100;

    // 최고 티어(챌린저) 초과 방지
    if (tierIndex >= tierList.length) {
      tierIndex = tierList.length - 1;
      currentTierExp = 100;
    }

    String calculatedTier = tierList[tierIndex];
    double progressRatio = (currentTierExp / 100.0).clamp(0.0, 1.0);

    // 🛑 최소 2회 레슨 미달 시 점수 무관 '일반회원' 고정
    bool isGeneralMember = lessonCount < 2;

    return TierProgressInfo(
      tierName: isGeneralMember ? '일반회원' : calculatedTier,
      totalExp: totalExp,
      currentTierExp: currentTierExp,
      progressRatio: progressRatio,
      isGeneralMember: isGeneralMember,
    );
  }
}
