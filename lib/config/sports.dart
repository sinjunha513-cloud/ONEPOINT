import 'package:flutter/material.dart';

const supportedSports = [
  '축구',
  '농구',
  '테니스',
  '배드민턴',
  '클라이밍',
  '수영',
  '골프',
  '복싱',
  '유도',
  '주짓수',
  '태권도',
  '필라테스',
  '요가',
  '탁구',
  '댄스',
  '크로스핏',
  '피겨',
  '스키',
  '헬스',
];

const coachWelcomeLevels = [
  '초급 환영',
  '초중급 환영',
  '중급 환영',
  '중고급 환영',
  '고급 환영',
];

IconData sportIcon(String sport) => switch (sport) {
      '축구' => Icons.sports_soccer,
      '농구' => Icons.sports_basketball,
      '테니스' || '배드민턴' => Icons.sports_tennis,
      '클라이밍' => Icons.hiking,
      '수영' => Icons.pool,
      '골프' => Icons.sports_golf,
      '복싱' => Icons.sports_mma,
      '유도' || '주짓수' || '태권도' => Icons.sports_martial_arts,
      '필라테스' || '크로스핏' => Icons.sports_gymnastics,
      '요가' => Icons.self_improvement,
      '탁구' => Icons.sports_tennis,
      '댄스' => Icons.emoji_people,
      '피겨' => Icons.ice_skating,
      '스키' => Icons.downhill_skiing,
      '헬스' => Icons.fitness_center,
      _ => Icons.sports,
    };
