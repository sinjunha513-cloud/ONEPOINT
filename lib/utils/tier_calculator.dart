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
    // Activity only: confirmed completions earn 20 EXP. Likes, subjective
    // evaluation scores and matching requests never inflate this indicator.
    int totalExp = (lessonCount < 0 ? 0 : lessonCount) * 20;

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
