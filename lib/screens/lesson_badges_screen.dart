import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/lesson_badge.dart';
import '../services/lesson_badge_service.dart';
import '../widget/lesson_badge_emblem.dart';
import 'lesson_requests_screen.dart';

const _background = Color(0xFF070D1B);
const _surface = Color(0xFF101A2C);
const _accent = Color(0xFFC6FF00);
const _muted = Color(0xFFABB5C8);

class LessonBadgesScreen extends StatefulWidget {
  final LessonBadgeService? service;

  const LessonBadgesScreen({super.key, this.service});

  @override
  State<LessonBadgesScreen> createState() => _LessonBadgesScreenState();
}

class _LessonBadgesScreenState extends State<LessonBadgesScreen> {
  late final LessonBadgeService _service;
  late Stream<List<LessonBadge>> _badges;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LessonBadgeService();
    _badges = _service.earnedBadges();
  }

  void _openLessons() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LessonRequestsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text('나의 시그니처 뱃지'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<LessonBadge>>(
          stream: _badges,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_rounded,
                title: '뱃지를 불러오지 못했어요',
                message: _badgeErrorMessage(snapshot.error),
                action: '다시 시도',
                onPressed: () => setState(() {
                  _badges = _service.earnedBadges();
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: _accent,
                  semanticsLabel: '시그니처 뱃지 불러오는 중',
                ),
              );
            }
            final badges = snapshot.data!;
            final signatureCount = badges
                .map((badge) =>
                    badge.signatureBadgeId ??
                    '${badge.instructorUid}|${badge.signatureMove}|${badge.sport}')
                .toSet()
                .length;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SIGNATURE COLLECTION',
                                style: TextStyle(
                                    color: _accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2)),
                            const SizedBox(height: 12),
                            const Text('함께한 레슨을,\n나만의 컬렉션으로.',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 12),
                            const Text(
                              '앱 접속이 아닌, 코치가 참여를 확인한 레슨마다\n그 코치의 시그니처 기술 뱃지를 받아요.',
                              style: TextStyle(
                                  color: _muted, height: 1.6, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _CollectionStat(
                                      value: '${badges.length}',
                                      label: '인증된 레슨',
                                      valueKey:
                                          const Key('certified-lesson-count'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _CollectionStat(
                                      value: '$signatureCount',
                                      label: '모은 시그니처',
                                      valueKey: const Key('signature-count'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (badges.isNotEmpty) ...[
                              const SizedBox(height: 30),
                              const Text('레슨마다 쌓이는 나의 기록',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              const Text('같은 시그니처도 레슨에 참여할 때마다 하나씩.',
                                  style:
                                      TextStyle(color: _muted, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (badges.isEmpty)
                  SliverToBoxAdapter(
                    child: _MessageState(
                      icon: Icons.workspace_premium_outlined,
                      title: '수집된 뱃지가 없습니다.',
                      message: '레슨 참여 후 시그니처 뱃지를 수집하세요!',
                      action: '내 레슨 보러 가기',
                      onPressed: _openLessons,
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: badges.length,
                    itemBuilder: (context, index) {
                      final badge = badges[index];
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: _BadgeCard(
                              key: ValueKey('badge-${badge.id}'),
                              badge: badge,
                              onTap: () => _showBadge(badge),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showBadge(LessonBadge badge) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LessonBadgeEmblem(
              identity: _identity(badge),
              sport: badge.sport,
              colorIndex: badge.signatureBadgeColorIndex,
              size: 140,
            ),
            const SizedBox(height: 16),
            const Text('참여 인증 완료',
                style: TextStyle(
                    color: _accent, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(badge.signatureMove,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${badge.instructorName} 코치의 시그니처',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 15)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: _background, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: '종목', value: badge.sport),
                  const SizedBox(height: 16),
                  _DetailRow(
                      label: '참여 확인일', value: _awardDate(badge.awardedAt)),
                  const SizedBox(height: 16),
                  _DetailRow(label: '확인 코치', value: badge.instructorName),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('${badge.instructorName} 코치가 레슨 참여를 확인하고\n발급한 시그니처 뱃지예요.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.6)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  foregroundColor: _background,
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _identity(LessonBadge badge) =>
    badge.signatureBadgeId ??
    '${badge.instructorUid}|${badge.sport}|${badge.signatureMove}';

String _badgeErrorMessage(Object? error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' =>
        '연결 상태를 확인한 뒤 다시 시도해 주세요.',
      'permission-denied' => '뱃지 조회 권한이 없습니다. 관리자에게 문의해 주세요.',
      'unauthenticated' => '다시 로그인한 뒤 뱃지를 확인해 주세요.',
      _ => '뱃지 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
    };
  }
  return '뱃지 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
}

String _awardDate(DateTime? date) =>
    date == null ? '확인 중' : DateFormat('yyyy.MM.dd').format(date.toLocal());

class _BadgeCard extends StatelessWidget {
  final LessonBadge badge;
  final VoidCallback onTap;

  const _BadgeCard({super.key, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${badge.sport} · 참여 인증',
            style: const TextStyle(color: _accent, fontSize: 11)),
        const SizedBox(height: 6),
        Text(badge.signatureMove,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${badge.instructorName} 코치',
            style: const TextStyle(color: _muted, fontSize: 13)),
        const SizedBox(height: 4),
        Text('인증일 ${_awardDate(badge.awardedAt)}',
            style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );

    return Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final emblem = LessonBadgeEmblem(
                identity: _identity(badge),
                sport: badge.sport,
                colorIndex: badge.signatureBadgeColorIndex,
                size: 80);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  emblem,
                  const SizedBox(height: 12),
                  text,
                ],
              );
            }
            return Row(
              children: [
                emblem,
                const SizedBox(width: 16),
                Expanded(child: text),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white38, size: 20),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _CollectionStat extends StatelessWidget {
  final String value;
  final String label;
  final Key valueKey;

  const _CollectionStat(
      {required this.value, required this.label, required this.valueKey});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              key: valueKey,
              style: const TextStyle(
                  color: _accent, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 20,
        runSpacing: 6,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onPressed;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: _accent),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, height: 1.6)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                  child: Text(action),
                ),
              ],
            ),
          ),
        ),
      );
}
