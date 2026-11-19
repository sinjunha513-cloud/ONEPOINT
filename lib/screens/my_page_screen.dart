import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';
import '../config/sports.dart';
import '../models/lesson_badge.dart';
import '../services/auth_service.dart';
import '../services/lesson_badge_service.dart';
import '../services/matching_service.dart';
import '../services/coach_availability_service.dart';
import '../utils/tier_calculator.dart';
import '../widgets/onepoint_app_bar.dart';
import '../widgets/onepoint_icon.dart';
import '../widgets/profile_photo.dart';
import '../widgets/logout_confirmation.dart';
import 'admin_dashboard_screen.dart';
import 'coach_availability_screen.dart';
import 'lesson_badges_screen.dart';
import 'lesson_requests_screen.dart';
import 'login_screen.dart';
import 'payment_history_screen.dart';
import 'signature_badge_catalog_screen.dart';
import 'signup_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen(
      {super.key,
      this.firestore,
      this.auth,
      this.availabilityService,
      this.sessionService});
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final CoachAvailabilityService? availabilityService;
  final AuthService? sessionService;
  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  late final FirebaseFirestore _db =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final User? _user = _auth.currentUser;
  late final _badges =
      LessonBadgeService(firestore: _db, auth: _auth).earnedBadges();
  late final _lessons = MatchingService(firestore: _db, auth: _auth).lessons();
  bool _signingOut = false;

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _editProfile(Map<String, dynamic> data) async {
    final updated = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => SignupScreen(
                role: data['role'] as String? ?? 'student',
                isEditing: true,
                initialData: data)));
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('프로필 정보가 수정되었습니다!')));
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      if (!await confirmLogout(context) || !mounted) return;
      final service =
          widget.sessionService ?? AuthService(firestore: _db, auth: _auth);
      await service.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => LoginScreen(service: service)),
            (_) => false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그아웃하지 못했습니다. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _openSignatureBadges() async {
    final uid = _user?.uid;
    if (uid == null) return;
    var sport = '';
    try {
      sport = (await _db.collection('instructors').doc(uid).get())
              .data()?['sport'] as String? ??
          '';
    } catch (_) {}
    if (mounted) _open(SignatureBadgeCatalogScreen(sport: sport));
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }
    return Scaffold(
      appBar: OnepointAppBar(
          title: '마이페이지', showSectionTitle: false, firestore: _db, auth: _auth),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(_user!.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('프로필을 불러오지 못했습니다. 다시 로그인해 주세요.'));
          }
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: OnepointDesign.lime));
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('사용자 정보를 찾을 수 없습니다.'));
          }
          final name = data['name'] as String? ?? '회원';
          final role = data['role'] as String? ?? 'student';
          final photo = data['profileImage'] as String? ??
              data['photoUrl'] as String? ??
              '';
          final target = data['targetTier'] as String? ?? '목표 미설정';
          final tier = TierCalculator.calculateTierInfo(
            lessonCount: (data['lessonCount'] as num?)?.toInt() ?? 0,
            reviewScores: (data['reviewScores'] as List<dynamic>? ?? [])
                .whereType<num>()
                .map((n) => n.toDouble())
                .toList(),
            teacherMatchCount:
                (data['teacherMatchCount'] as num?)?.toInt() ?? 0,
            feedLikeCount: (data['feedLikeCount'] as num?)?.toInt() ?? 0,
          );
          return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: OnepointDesign.surface,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              key: const ValueKey('edit-profile-card'),
                              onTap: () => _editProfile(data),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  SizedBox(
                                      width: 59,
                                      height: 55,
                                      child: ClipOval(
                                          child: ProfilePhoto(
                                              image: photo,
                                              placeholder: const OnepointIcon(
                                                  'profile-avatar',
                                                  width: 59,
                                                  height: 55)))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const Text('나의 프로필',
                                            style: OnepointDesign.heading),
                                        const SizedBox(height: 4),
                                        Text('$name · ONEPOINT 회원',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: OnepointDesign.muted)),
                                      ])),
                                  const SizedBox(width: 8),
                                  const Text('수정 >',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: OnepointDesign.muted)),
                                ]),
                              )),
                        ),
                        const SizedBox(height: 16),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: _tierLabel('현재 티어', tier.tierName,
                                      OnepointDesign.lime)),
                              const SizedBox(width: 20),
                              Expanded(
                                  child: _tierLabel(
                                      '목표 티어', target, OnepointDesign.blue,
                                      right: true)),
                            ]),
                        const SizedBox(height: 20),
                        _calendarCard(role),
                        const SizedBox(height: 24),
                        _section('나의 뱃지', '전체보기 >',
                            () => _open(const LessonBadgesScreen())),
                        const SizedBox(height: 12),
                        StreamBuilder<List<LessonBadge>>(
                          stream: _badges,
                          builder: (context, badges) {
                            final count = badges.data?.length;
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LayoutBuilder(
                                      builder: (context, constraints) {
                                    final height =
                                        ((constraints.maxWidth - 24) /
                                                3 *
                                                180 /
                                                114)
                                            .clamp(140.0, 180.0);
                                    return SizedBox(
                                        height: height,
                                        child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                  child: _achievement(
                                                      count != null && count > 0
                                                          ? 'badge-medal'
                                                          : 'lock',
                                                      '첫 레슨',
                                                      count == null
                                                          ? '확인 중'
                                                          : count > 0
                                                              ? '획득 완료'
                                                              : '아직 미획득')),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: _achievement(
                                                      'trophy',
                                                      '레슨 달성',
                                                      count == null
                                                          ? '확인 중'
                                                          : '$count개 획득')),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: _achievement(
                                                      'lock', '도전 중', '다음 레슨')),
                                            ]));
                                  }),
                                  if (badges.hasError)
                                    const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text('뱃지를 불러오지 못했습니다.',
                                            style: TextStyle(
                                                color: OnepointDesign.muted,
                                                fontSize: 12))),
                                ]);
                          },
                        ),
                        const SizedBox(height: 36),
                        _section('나의 레슨', '전체보기 >',
                            () => _open(const LessonRequestsScreen())),
                        const SizedBox(height: 12),
                        _lessonCards(),
                        const SizedBox(height: 32),
                        _accountActions(data, role, tier.totalExp),
                      ]),
                ),
              ));
        },
      ),
    );
  }

  Widget _calendarCard(String role) {
    final coach = role == 'coach';
    return Material(
      color: OnepointDesign.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(coach ? 'my-availability-card' : 'my-schedule-card'),
        onTap: () => _open(coach
            ? CoachAvailabilityScreen(service: widget.availabilityService)
            : const LessonRequestsScreen()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded,
                color: OnepointDesign.lime, size: 32),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(coach ? '날짜·시간 등록' : '레슨 날짜·시간',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                      coach
                          ? '수업 가능한 날짜와 시간을 등록하세요. (KST)'
                          : '예약한 레슨 날짜를 확인하고 변경하세요.',
                      style: const TextStyle(
                          color: OnepointDesign.muted,
                          fontSize: 12,
                          height: 1.4)),
                ])),
            const SizedBox(width: 8),
            Text(coach ? '등록 >' : '확인 >',
                style:
                    const TextStyle(color: OnepointDesign.lime, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _tierLabel(String label, String value, Color color,
          {bool right = false}) =>
      Column(
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: OnepointDesign.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _section(String label, String action, VoidCallback onTap) =>
      Row(children: [
        Expanded(child: Text(label, style: OnepointDesign.heading)),
        TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
                foregroundColor: OnepointDesign.muted,
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: Text(action, style: const TextStyle(fontSize: 12))),
      ]);

  Widget _achievement(String asset, String title, String detail) => Material(
        color: OnepointDesign.surface,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: () => _open(const LessonBadgesScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OnepointIcon(asset,
                        width: asset == 'badge-medal'
                            ? 30
                            : asset == 'trophy'
                                ? 30
                                : 33,
                        height: asset == 'badge-medal'
                            ? 37
                            : asset == 'trophy'
                                ? 30
                                : 33),
                    const SizedBox(height: 12),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(detail,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10, color: OnepointDesign.muted)),
                  ]),
            )),
      );

  Widget _lessonCards() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _lessons,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('레슨 내역을 불러오지 못했습니다. 전체보기에서 다시 시도해 주세요.');
          }
          if (!snapshot.hasData) return _message('레슨을 확인하고 있습니다.');
          final docs = snapshot.data!.docs
              .where((d) => ['pending', 'accepted', 'completed']
                  .contains(d.data()['status']))
              .toList();
          docs.sort((a, b) {
            final aDone = a.data()['status'] == 'completed',
                bDone = b.data()['status'] == 'completed';
            if (aDone != bDone) return aDone ? 1 : -1;
            final aDate = a.data()['updatedAt'] ?? a.data()['createdAt'],
                bDate = b.data()['updatedAt'] ?? b.data()['createdAt'];
            return (bDate is Timestamp ? bDate.millisecondsSinceEpoch : 0)
                .compareTo(
                    aDate is Timestamp ? aDate.millisecondsSinceEpoch : 0);
          });
          if (docs.isEmpty) {
            return _message('아직 등록된 레슨이 없습니다.\n코치에게 첫 레슨을 신청해보세요.');
          }
          return Column(children: [
            for (final doc in docs.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: OnepointDesign.surface,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      key: ValueKey('my-lesson-${doc.id}'),
                      onTap: () => _open(const LessonRequestsScreen()),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _lessonContent(doc.data()))),
                ),
              )
          ]);
        },
      );

  Widget _lessonContent(Map<String, dynamic> data) {
    final status = data['status'], completed = status == 'completed';
    final label = completed
        ? '레슨 완료'
        : status == 'pending'
            ? '수락 대기'
            : '레슨 진행 중';
    final sport = data['sport'] as String? ?? '스포츠';
    final title = data['signatureMove'] as String? ?? '$sport 레슨';
    final mine = data['instructorUid'] == _user?.uid;
    final person = data[mine ? 'studentName' : 'instructorName'] as String? ??
        (mine ? '수강생' : '코치');
    final progress = data['progress'];
    final value = completed
        ? 1.0
        : progress is num
            ? progress.toDouble().clamp(0.0, 1.0)
            : 0.0;
    final artwork = switch (sport) {
      '축구' => 'lesson-football',
      '농구' => 'sport-basketball',
      '테니스' => 'sport-tennis',
      '배드민턴' => 'badminton',
      _ => null
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: OnepointDesign.lime,
                    fontSize: 12,
                    fontWeight: FontWeight.w600))),
        const Text('상세보기 >',
            style: TextStyle(color: OnepointDesign.muted, fontSize: 11))
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(14)),
            child: Center(
                child: artwork == null
                    ? Icon(sportIcon(sport), color: Colors.white)
                    : OnepointIcon(artwork, width: 27, height: 27))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('$person · $sport',
              style:
                  const TextStyle(color: OnepointDesign.muted, fontSize: 12)),
        ])),
      ]),
      const SizedBox(height: 14),
      if (completed || progress is num) ...[
        Text('${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: OnepointDesign.lime, fontSize: 11)),
        const SizedBox(height: 5),
      ],
      ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: const Color(0xFFDADADA),
              color: OnepointDesign.lime)),
    ]);
  }

  Widget _message(String text) => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: OnepointDesign.surface,
          borderRadius: BorderRadius.circular(16)),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: OnepointDesign.muted, fontSize: 13, height: 1.5)));

  Widget _accountActions(Map<String, dynamic> data, String role, int exp) =>
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('my-account-actions'),
          tilePadding: EdgeInsets.zero,
          iconColor: OnepointDesign.muted,
          collapsedIconColor: OnepointDesign.muted,
          title: const Text('계정 및 활동 관리',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          subtitle: Text('누적 EXP $exp',
              style:
                  const TextStyle(color: OnepointDesign.muted, fontSize: 12)),
          children: [
            _action(
                '프로필 및 정보 수정하기', Icons.edit_outlined, () => _editProfile(data)),
            _action(
                role == 'admin'
                    ? '결제 관리'
                    : role == 'coach'
                        ? '정산 예정 내역'
                        : '나의 결제 내역',
                Icons.payments_outlined,
                () => _open(PaymentHistoryScreen(
                    adminMode: role == 'admin', coachMode: role == 'coach'))),
            if (role == 'coach') ...[
              _action('레슨 가능 날짜·시간 관리', Icons.event_available_outlined,
                  () => _open(const CoachAvailabilityScreen())),
              _action('시그니처 뱃지 등록·관리', Icons.workspace_premium_outlined,
                  _openSignatureBadges),
            ],
            if (role == 'admin')
              _action('관리자 대시보드', Icons.admin_panel_settings_outlined,
                  () => _open(const AdminDashboardScreen())),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('나의 포부 / 한 줄 소개',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                    data['aspirations'] as String? ??
                        data['bio'] as String? ??
                        '등록된 포부가 없습니다.',
                    style: const TextStyle(color: OnepointDesign.muted))),
            if ((data['videoUrl'] as String? ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(data['videoUrl'] as String,
                      style: const TextStyle(
                          color: OnepointDesign.blue, fontSize: 12))),
            _action(_signingOut ? '로그아웃 중...' : '로그아웃', Icons.logout,
                _signingOut ? null : _signOut),
          ],
        ),
      );

  Widget _action(String title, IconData icon, VoidCallback? onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: OnepointDesign.lime, size: 22),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right,
          color: OnepointDesign.muted, size: 20),
      onTap: onTap);
}
