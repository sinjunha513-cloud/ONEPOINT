import '../config/sports.dart';

class CoachCandidate {
  const CoachCandidate(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

class CoachRecommendation {
  const CoachRecommendation(this.coach, this.score, this.reasons);
  final CoachCandidate coach;
  final int score;
  final List<String> reasons;
}

/// Transparent content matching. Names, email, photos and EXP tiers do not
/// measure sporting ability and are deliberately excluded from ranking.
class CoachRecommendationService {
  static const levels = ['입문', '초급', '중급', '고급'];
  static const _welcome = {
    '초급 환영': ['입문', '초급'],
    '초중급 환영': ['초급', '중급'],
    '중급 환영': ['중급'],
    '중고급 환영': ['중급', '고급'],
    '고급 환영': ['고급'],
  };
  static const _aliases = [
    ['패스', '패싱', 'passing'],
    ['드리블', 'dribbling'],
    ['슈팅', '슛', 'shooting'],
    ['서브', '서비스', 'serve'],
    ['체력', '피트니스', 'fitness'],
    ['다이어트', '체중감량', '감량'],
    ['근력', '웨이트', '근육'],
    ['자세', '폼', 'form'],
    ['입문', '초보', '처음'],
    ['유연성', '스트레칭'],
  ];
  static String _text(dynamic value) => value is String ? value.trim() : '';
  static String _compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^가-힣a-z0-9]'), '');
  static List<String> _goals(String text) {
    const ignored = {
      '배우고',
      '싶어요',
      '싶습니다',
      '하고',
      '싶고',
      '목표',
      '레슨',
      '수업',
      '운동',
      '스포츠',
      '잘하고',
      '잘하고싶어요',
      '좋아요',
      '원해요',
      '위해',
      '하기',
      '싶은',
      '하는',
      '배우는',
      '연습',
      '코치',
      '합니다',
      '입니다'
    };
    final result = <String>{};
    for (final raw in text.toLowerCase().split(RegExp(r'[^가-힣a-z0-9]+'))) {
      var word = raw;
      if (word.length > 2) {
        word =
            word.replaceFirst(RegExp(r'(으로|에서|까지|에게|을|를|은|는|이|가|도|와|과)$'), '');
      }
      if (word.length >= 2 &&
          !ignored.contains(word) &&
          !supportedSports.contains(word)) {
        result.add(word);
      }
      if (result.length >= 20) break;
    }
    return result.toList();
  }

  static bool _matches(String goal, String coach) {
    if (coach.contains(goal)) return true;
    for (final group in _aliases) {
      if (group.contains(goal) && group.any(coach.contains)) return true;
    }
    return false;
  }

  static int _rotation(String value) {
    var hash = 0;
    for (final c in value.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    hash = (hash * 48271) % 2147483647;
    hash ^= hash >> 13;
    hash = (hash * 48271) % 2147483647;
    return hash ^ (hash >> 16);
  }

  List<CoachRecommendation> rank(
      {required List<CoachCandidate> coaches,
      required Map<String, dynamic> profile,
      required String userUid,
      String selectedSport = '전체',
      DateTime? day}) {
    final explicit = _text(profile['preferredSport']);
    final goalText =
        '${_text(profile['learningGoal'])} ${_text(profile['aspirations'] ?? profile['bio'])}';
    final preferred = supportedSports.contains(explicit)
        ? {explicit}
        : supportedSports
            .where((sport) => _compact(goalText).contains(_compact(sport)))
            .toSet();
    final level = _text(profile['experienceLevel']);
    final goals = _goals(goalText);
    final result = <CoachRecommendation>[];
    for (final coach in coaches) {
      final d = coach.data, sport = _text(coach.data['sport']);
      if (d['status'] != 'approved' ||
          coach.id == userUid ||
          d['uid'] == userUid) {
        continue;
      }
      if (selectedSport != '전체' && sport != selectedSport) continue;
      if (selectedSport == '전체' &&
          preferred.isNotEmpty &&
          !preferred.contains(sport)) {
        continue;
      }
      var score = 0;
      final reasons = <String>[];
      if (preferred.contains(sport)) {
        score += 50;
        reasons.add('관심 종목 $sport');
      } else if (selectedSport != '전체') {
        reasons.add('선택한 종목 $sport');
      }
      if (levels.contains(level) &&
          (_welcome[d['lessonLevel']]?.contains(level) ?? false)) {
        score += 30;
        reasons.add('$level 수준에 맞는 수업');
      }
      final content =
          _compact('${_text(d['signatureMove'])} ${_text(d['career'])}');
      final matched = goals.where((word) => _matches(word, content)).toList();
      if (matched.isNotEmpty) {
        final denominator = goals.length < 4 ? goals.length : 4;
        score += (20 * (matched.length / denominator).clamp(0, 1)).round();
        reasons.add('${matched.take(2).join('·')} 지도');
      }
      if (reasons.isEmpty) reasons.add('승인된 코치를 둘러보세요');
      result.add(CoachRecommendation(coach, score, List.unmodifiable(reasons)));
    }
    final date = day ?? DateTime.now().toUtc().add(const Duration(hours: 9));
    final seed = '$userUid/${date.year}-${date.month}-${date.day}';
    result.sort((a, b) {
      final relevance = b.score.compareTo(a.score);
      if (relevance != 0) return relevance;
      final rotation = _rotation('$seed/${a.coach.id}')
          .compareTo(_rotation('$seed/${b.coach.id}'));
      return rotation != 0 ? rotation : a.coach.id.compareTo(b.coach.id);
    });
    return result;
  }
}
