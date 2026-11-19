import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/coach_recommendation_service.dart';

CoachCandidate coach(String id,
        {String sport = '축구',
        String level = '초급 환영',
        String skill = '패스',
        String status = 'approved',
        String rating = '0'}) =>
    CoachCandidate(id, {
      'uid': id,
      'name': '코치 $id',
      'sport': sport,
      'lessonLevel': level,
      'signatureMove': skill,
      'status': status,
      'rating': rating
    });
void main() {
  final service = CoachRecommendationService();
  final day = DateTime(2036, 1, 1);
  test(
      'signup sport, level and learning goal rank relevant approved coaches first',
      () {
    final result = service.rank(coaches: [
      coach('advanced', level: '고급 환영', skill: '슈팅', rating: '5'),
      coach('basketball', sport: '농구'),
      coach('match', skill: '패스 자세 교정'),
      coach('pending', status: 'pending')
    ], profile: {
      'preferredSport': '축구',
      'experienceLevel': '초급',
      'learningGoal': '패스 자세'
    }, userUid: 'student', day: day);
    expect(result.map((r) => r.coach.id), ['match', 'advanced']);
    expect(result.first.score, 100);
    expect(result.first.reasons, contains('초급 수준에 맞는 수업'));
  });
  test('legacy aspirations supply sport and skill without a new signup', () {
    final result = service.rank(coaches: [
      coach('basketball', sport: '농구'),
      coach('shoot', skill: '슈팅'),
      coach('pass', skill: '패스')
    ], profile: {
      'aspirations': '축구 패스를 배우고 싶어요'
    }, userUid: 'student', day: day);
    expect(result.first.coach.id, 'pass');
    expect(result.every((r) => r.coach.data['sport'] == '축구'), isTrue);
  });
  test(
      'manual sport selection overrides onboarding sport without changing the profile',
      () {
    final result = service.rank(
        coaches: [coach('football'), coach('tennis', sport: '테니스')],
        profile: {'preferredSport': '축구'},
        userUid: 'student',
        selectedSport: '테니스',
        day: day);
    expect(result.single.coach.id, 'tennis');
  });
  test(
      'names, email, photos, EXP tier and unverified ratings cannot change relevance',
      () {
    final candidates = [coach('a'), coach('b', rating: '5')];
    final first = service.rank(
        coaches: candidates, profile: {}, userUid: 'member', day: day);
    final second = service.rank(
        coaches: candidates,
        profile: {
          'name': 'a',
          'email': 'a@example.com',
          'profileImage': 'a',
          'targetTier': '챌린저',
          'lessonCount': 999
        },
        userUid: 'member',
        day: day);
    expect(second.map((r) => r.coach.id), first.map((r) => r.coach.id));
    expect(second.every((r) => r.score == 0), isTrue);
  });
  test(
      'ties are stable within a day and rotate across days including new coaches',
      () {
    final candidates = [
      coach('new'),
      coach('old', rating: '5'),
      coach('third')
    ];
    String top(DateTime d) => service
        .rank(coaches: candidates, profile: {}, userUid: 'member', day: d)
        .first
        .coach
        .id;
    expect(top(day), top(day));
    expect({for (var i = 0; i < 60; i++) top(day.add(Duration(days: i)))},
        hasLength(greaterThan(1)));
  });
  test(
      'no matching sport produces an honest empty result and own coach is excluded',
      () {
    expect(
        service.rank(
            coaches: [coach('a')],
            profile: {'preferredSport': '수영'},
            userUid: 'member',
            day: day),
        isEmpty);
    expect(
        service.rank(
            coaches: [coach('member')],
            profile: {},
            userUid: 'member',
            day: day),
        isEmpty);
  });
}
