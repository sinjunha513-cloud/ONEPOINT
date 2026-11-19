import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/lesson_service.dart';
import 'profile_screen.dart';
import 'shortform_feed_screen.dart';
import 'lesson_requests_screen.dart';
import '../config/sports.dart';
import '../config/signature_badge_palette.dart';
import '../models/lesson_slot.dart';
import 'lesson_slot_picker_screen.dart';
import '../widgets/onepoint_app_bar.dart';
import '../widgets/onepoint_icon.dart';
import '../config/onepoint_design.dart';
import '../services/matching_service.dart';
import '../services/coach_recommendation_service.dart';
import '../models/lesson_badge.dart';
import 'lesson_badges_screen.dart';
import '../services/coupon_service.dart';
import '../widgets/monthly_lesson_goal_card.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.firestore, this.auth});

  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String selectedSport = '전체';
  late final FirebaseFirestore _db =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final LessonService _lessonService =
      LessonService(firestore: _db, auth: _auth);
  late final _lessons = MatchingService(firestore: _db, auth: _auth).lessons();
  late final _recommendations = CoachRecommendationService();
  late final _coupons = CouponService(firestore: _db, auth: _auth);
  late final _recommendationProfile = _auth.currentUser == null
      ? null
      : _db.collection('users').doc(_auth.currentUser!.uid).snapshots();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _coaches =
      _lessonService.getInstructors(selectedSport);

  void _selectSport(String sport) {
    if (sport == selectedSport) return;
    setState(() {
      selectedSport = sport;
      _coaches = _lessonService.getInstructors(sport);
    });
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: OnepointAppBar(
          title: '홈',
          showSectionTitle: false,
          firestore: _db,
          auth: _auth,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _coaches,
          builder: (context, coaches) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _lessons,
            builder: (context, lessons) {
              final docs = coaches.data?.docs ?? [];
              final requests = lessons.data?.docs ?? [];
              final pending =
                  requests.where((d) => d.data()['status'] == 'pending').length;
              final accepted = requests
                  .where((d) => d.data()['status'] == 'accepted')
                  .length;
              final badges = requests
                  .where((d) =>
                      d.data()['studentUid'] == _auth.currentUser?.uid &&
                      LessonBadge.fromLesson(d.id, d.data()) != null)
                  .length;
              final loaded = lessons.hasData && !lessons.hasError;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: _recommendationProfile,
                              builder: (context, profile) =>
                                  MonthlyLessonGoalCard(
                                      lessons:
                                          requests.map((doc) => doc.data()),
                                      uid: _auth.currentUser?.uid ?? '',
                                      role: profile.data?.data()?['role']
                                              as String? ??
                                          'student',
                                      loaded: loaded,
                                      hasError:
                                          lessons.hasError || profile.hasError,
                                      service: _coupons)),
                          const SizedBox(height: 14),
                          IntrinsicHeight(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                      _recommendation(coaches),
                                      const SizedBox(height: 14),
                                      Expanded(
                                          child: _tile(
                                        onTap: () =>
                                            _open(const LessonBadgesScreen()),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Row(children: [
                                                Expanded(
                                                    child: Text('나의 뱃지',
                                                        style: OnepointDesign
                                                            .heading)),
                                                OnepointIcon('badge',
                                                    width: 20, height: 26)
                                              ]),
                                              const SizedBox(height: 20),
                                              Text(loaded ? '$badges개 획득' : '—',
                                                  style: const TextStyle(
                                                      fontSize: 26,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ]),
                                      )),
                                    ])),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                      _tile(
                                          onTap: () => _open(
                                              const LessonRequestsScreen()),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text('레슨 신청 현황',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 17)),
                                                const SizedBox(height: 16),
                                                _status('수락 대기',
                                                    loaded ? '$pending' : '—'),
                                                const SizedBox(height: 8),
                                                _status('레슨 확정',
                                                    loaded ? '$accepted' : '—'),
                                              ])),
                                      const SizedBox(height: 14),
                                      Expanded(
                                          child: _tile(
                                        padding: EdgeInsets.zero,
                                        onTap: () =>
                                            _open(const ShortformFeedScreen()),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Expanded(
                                                  child: Center(
                                                      child: OnepointIcon(
                                                          'video-upload',
                                                          width: 48,
                                                          height: 28))),
                                              Container(
                                                  padding:
                                                      const EdgeInsets.all(14),
                                                  decoration: BoxDecoration(
                                                      color:
                                                          OnepointDesign.lime,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16)),
                                                  child: const Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text('레슨 영상 피드',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .black,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600)),
                                                        SizedBox(height: 4),
                                                        Text('코칭 영상을 확인해보세요.',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .black54,
                                                                fontSize: 10)),
                                                      ])),
                                            ]),
                                      )),
                                    ])),
                              ])),
                          const SizedBox(height: 24),
                          Row(children: [
                            const Expanded(
                                child: Text('종목별 코치 찾기',
                                    style: OnepointDesign.heading)),
                            TextButton(
                                onPressed: _chooseSport,
                                child: const Text('전체 종목',
                                    style:
                                        TextStyle(color: OnepointDesign.muted)))
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            for (final sport in ['축구', '농구', '테니스', '배드민턴'])
                              Expanded(
                                  child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: _tile(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  color: selectedSport == sport
                                      ? OnepointDesign.lime
                                      : OnepointDesign.surface,
                                  onTap: () => _selectSport(sport),
                                  child: Column(children: [
                                    OnepointIcon(
                                      switch (sport) {
                                        '축구' => 'sport-football',
                                        '농구' => 'sport-basketball',
                                        '테니스' => 'sport-tennis',
                                        _ => 'badminton'
                                      },
                                      width: 22,
                                      height: 22,
                                      color: selectedSport == sport
                                          ? Colors.black
                                          : OnepointDesign.lime,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(sport,
                                        style: TextStyle(
                                            color: selectedSport == sport
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 11)),
                                  ]),
                                ),
                              ))
                          ]),
                          const SizedBox(height: 16),
                          if (!['축구', '농구', '테니스', '배드민턴']
                              .contains(selectedSport))
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text('$selectedSport 코치',
                                    style: OnepointDesign.heading)),
                          if (coaches.hasError)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(children: [
                                Text(
                                    coaches.error is FirebaseException &&
                                            (coaches.error as FirebaseException)
                                                    .code ==
                                                'permission-denied'
                                        ? '코치 목록 조회 권한을 확인하지 못했습니다. 다시 로그인해 주세요.'
                                        : '코치 목록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                TextButton(
                                    onPressed: () => setState(() => _coaches =
                                        _lessonService
                                            .getInstructors(selectedSport)),
                                    child: const Text('다시 시도',
                                        style: TextStyle(
                                            color: OnepointDesign.lime))),
                              ]),
                            )
                          else if (!coaches.hasData)
                            const Center(
                                child: CircularProgressIndicator(
                                    color: OnepointDesign.lime))
                          else if (docs.isEmpty)
                            Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('현재 등록된 $selectedSport 코치가 없습니다.',
                                    textAlign: TextAlign.center))
                          else
                            for (final doc in docs)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _tile(
                                    onTap: () => _showInstructorDetail(
                                        context, doc.id, doc.data()),
                                    child: Row(children: [
                                      Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(9)),
                                          child: Icon(
                                              sportIcon(doc.data()['sport']
                                                      as String? ??
                                                  selectedSport),
                                              color: Colors.white)),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                doc.data()['signatureMove']
                                                        as String? ??
                                                    "${doc.data()['sport'] ?? '스포츠'} 레슨",
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            Text(
                                                '${doc.data()['name'] ?? '코치'} · ${doc.data()['lessonLevel'] ?? doc.data()['sport'] ?? '스포츠'}',
                                                style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 12)),
                                          ])),
                                      const Icon(Icons.chevron_right,
                                          color: OnepointDesign.lime),
                                    ]),
                                  )),
                        ]),
                  ),
                ),
              );
            },
          ),
        ),
      );

  Widget _recommendation(
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _recommendationProfile,
          builder: (context, profile) =>
              _recommendedCard(snapshot, profile.data?.data() ?? {}));

  Widget _recommendedCard(
      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
      Map<String, dynamic> profile) {
    final docs = snapshot.data?.docs ?? [];
    final ranked = _recommendations.rank(
        coaches: [for (final d in docs) CoachCandidate(d.id, d.data())],
        profile: profile,
        userUid: _auth.currentUser?.uid ?? '',
        selectedSport: selectedSport);
    final recommendation = ranked.isEmpty ? null : ranked.first;
    final coach = recommendation?.coach;
    final name = coach?.data['name'] as String? ??
        (snapshot.hasError
            ? '연결 확인'
            : snapshot.hasData
                ? '맞춤 코치 준비 중'
                : '불러오는 중');
    return _tile(
      color: OnepointDesign.lime,
      onTap: coach == null
          ? null
          : () => _showInstructorDetail(context, coach.id, coach.data),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('추천 코치',
            style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
            height: 128,
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130, maxHeight: 130),
              child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(fit: StackFit.expand, children: [
                    const ExcludeSemantics(
                        child: CircularProgressIndicator(
                            value: .75,
                            strokeWidth: 9,
                            color: Colors.white,
                            backgroundColor: Colors.transparent)),
                    Center(
                        child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                      coach?.data['sport'] as String? ??
                                          (selectedSport == '전체'
                                              ? '스포츠'
                                              : selectedSport),
                                      style: const TextStyle(
                                          color: Colors.black54, fontSize: 12)),
                                ]))),
                  ])),
            ))),
        if (recommendation != null) ...[
          const SizedBox(height: 8),
          Text(recommendation.reasons.take(2).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.black87, fontSize: 11, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _tile(
          {required Widget child,
          Color color = OnepointDesign.surface,
          VoidCallback? onTap,
          EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) =>
      Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      );

  Widget _status(String label, String count) => Row(children: [
        Flexible(
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: OnepointDesign.lime,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(label,
                    style:
                        const TextStyle(color: Colors.black, fontSize: 11)))),
        const SizedBox(width: 10),
        Text(count, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]);

  void _chooseSport() => showModalBottomSheet<void>(
      context: context,
      backgroundColor: OnepointDesign.surface,
      isScrollControlled: true,
      builder: (context) => SafeArea(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final sport in ['전체', ...supportedSports])
                ChoiceChip(
                  label: Text(sport),
                  selected: selectedSport == sport,
                  selectedColor: OnepointDesign.lime,
                  onSelected: (_) {
                    _selectSport(sport);
                    Navigator.pop(context);
                  },
                )
            ]),
          )));

  // 코치 상세정보 모달창
  void _showInstructorDetail(
      BuildContext context, String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        var requesting = false;
        final badgeColor = signatureBadgeColor(
            (data['signatureBadgeColorIndex'] as num?)?.toInt(),
            legacyIdentity: data['signatureMove'] as String? ?? docId);
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          data['name'] ?? '',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // ★ 상대방 프로필 이동 버튼 (오류 수정됨: targetUserId만 전달)
                      TextButton.icon(
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: const Text('프로필 보기'),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(
                                targetUserId: (data['uid'] as String?) ?? docId,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('종목: ${data['sport']}'),
                  Text('수업 난이도: ${data['lessonLevel'] ?? '코치와 상담 후 결정'}'),
                  Text('이력: ${data['career']}'),
                  Text('평점: ★ ${data['rating']}'),
                  if ((data['signatureMove'] as String? ?? '')
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: badgeColor.withValues(alpha: .45)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.workspace_premium,
                              color: badgeColor, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${data['signatureMove']}',
                                    style: TextStyle(
                                        color: badgeColor,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text('레슨에 참여하고 코치의 시그니처 뱃지를 모아 보세요.',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: requesting
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final coachUid = data['uid'] as String?;
                              if (coachUid == null || coachUid.isEmpty) {
                                messenger.showSnackBar(const SnackBar(
                                  content: Text('코치 계정 정보를 확인할 수 없습니다.'),
                                ));
                                return;
                              }
                              final slot = await Navigator.push<LessonSlot>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LessonSlotPickerScreen(
                                    coachUid: coachUid,
                                    coachName: data['name'] as String? ?? '코치',
                                  ),
                                ),
                              );
                              if (slot == null || !context.mounted) return;
                              setModalState(() => requesting = true);
                              try {
                                await _lessonService.requestLesson(
                                  instructorId: docId,
                                  instructorName:
                                      data['name'] as String? ?? '코치',
                                  coachUid: coachUid,
                                  slotId: slot.id,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                messenger.showSnackBar(SnackBar(
                                  content:
                                      Text('${data['name']} 코치님께 레슨을 신청했습니다!'),
                                ));
                              } catch (e) {
                                if (context.mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                        content: Text(_lessonRequestError(e))),
                                  );
                                }
                              } finally {
                                if (context.mounted) {
                                  setModalState(() => requesting = false);
                                }
                              }
                            },
                      child: requesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('레슨 신청하기'),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _lessonRequestError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          '레슨 신청 권한을 확인할 수 없습니다. 수강생·관리자 계정인지와 코치 승인 상태를 확인해 주세요.',
        'unavailable' ||
        'deadline-exceeded' =>
          '서버에 연결할 수 없습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
        'aborted' => '동시에 처리된 요청이 있습니다. 잠시 후 다시 시도해 주세요.',
        'already-exists' => '이미 신청했거나 진행 중인 레슨이 있습니다.',
        _ => '레슨을 신청하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      };
    }
    return '레슨을 신청하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }
}
