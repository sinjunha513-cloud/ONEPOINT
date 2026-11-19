import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';
import '../models/monthly_lesson_goal.dart';
import '../screens/coupon_wallet_screen.dart';
import '../services/coupon_service.dart';

class MonthlyLessonGoalCard extends StatefulWidget {
  const MonthlyLessonGoalCard(
      {super.key,
      required this.lessons,
      required this.uid,
      required this.role,
      required this.loaded,
      required this.hasError,
      required this.service});
  final Iterable<Map<String, dynamic>> lessons;
  final String uid, role;
  final bool loaded, hasError;
  final CouponService service;
  @override
  State<MonthlyLessonGoalCard> createState() => _MonthlyLessonGoalCardState();
}

class _MonthlyLessonGoalCardState extends State<MonthlyLessonGoalCard>
    with WidgetsBindingObserver {
  late final _coupons = widget.service.coupons();
  late final Timer _clock;
  bool _claiming = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      await widget.service.claim();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('10% 할인권을 받았어요. 내 할인권에서 확인해 주세요.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(couponError(error))));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = MonthlyLessonGoal(
        lessons: widget.lessons, uid: widget.uid, role: widget.role);
    final loaded = widget.loaded && !widget.hasError;
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: goal.eligible ? _coupons : null,
                builder: (context, snapshot) {
                  final claimed = snapshot.data?.docs
                          .any((doc) => doc.id == 'monthly_${goal.monthKey}') ??
                      false;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('${goal.monthLabel} 나의 레슨 현황',
                                    style: OnepointDesign.heading),
                                const SizedBox(height: 6),
                                const Text('월 목표 20회',
                                    key: ValueKey('monthly-goal-target'),
                                    style: TextStyle(
                                        color: OnepointDesign.lime,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 5),
                                Text(
                                    widget.hasError
                                        ? '레슨 현황을 불러오지 못했습니다.'
                                        : loaded
                                            ? '${widget.role == 'coach' ? '진행 완료' : widget.role == 'student' ? '수강 완료' : '완료'} ${goal.count}회'
                                            : '레슨 현황을 확인하고 있어요.',
                                    style: const TextStyle(
                                        color: OnepointDesign.muted,
                                        fontSize: 12)),
                              ])),
                          const SizedBox(width: 12),
                          SizedBox.square(
                              dimension: 64,
                              child:
                                  Stack(alignment: Alignment.center, children: [
                                SizedBox.expand(
                                    child: CircularProgressIndicator(
                                        value: loaded ? goal.percent / 100 : 0,
                                        backgroundColor: Colors.white10,
                                        color: OnepointDesign.lime,
                                        strokeWidth: 6)),
                                Text(loaded ? '${goal.percent}%' : '—%',
                                    key: const ValueKey('monthly-goal-percent'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                              ]))
                        ]),
                        const SizedBox(height: 14),
                        Text(
                            loaded
                                ? goal.targetReached
                                    ? '100% 달성! 이번 달 목표를 이뤘어요.'
                                    : '100%까지 ${goal.remainingPercent}%, ${goal.remainingLessons}회 남았어요.'
                                : '완료한 레슨만 월간 목표에 반영돼요.',
                            style: TextStyle(
                                color: loaded && goal.targetReached
                                    ? OnepointDesign.lime
                                    : Colors.white70,
                                fontSize: 12)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Expanded(
                              child: Text('매달 1일 초기화 · 한국 시간',
                                  style: TextStyle(
                                      color: OnepointDesign.muted,
                                      fontSize: 10))),
                          if (goal.eligible)
                            TextButton(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CouponWalletScreen(
                                            service: widget.service))),
                                child: const Text('내 할인권'))
                        ]),
                        if (loaded && goal.achieved)
                          FilledButton(
                              onPressed: _claiming ||
                                      claimed ||
                                      !snapshot.hasData ||
                                      snapshot.hasError
                                  ? null
                                  : _claim,
                              child: Text(_claiming
                                  ? '발급 중…'
                                  : claimed
                                      ? '이번 달 할인권 받기 완료'
                                      : '10% 할인권 받기')),
                        if (snapshot.hasError)
                          const Text('할인권 정보를 불러오지 못했습니다.',
                              style: TextStyle(
                                  color: OnepointDesign.muted, fontSize: 11)),
                      ]);
                })));
  }
}
