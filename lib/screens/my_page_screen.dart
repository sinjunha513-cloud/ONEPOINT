import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'admin_dashboard_screen.dart';
import 'lesson_badges_screen.dart';
import 'payment_history_screen.dart';
import '../utils/tier_calculator.dart';
import '../widgets/profile_photo.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'signature_badge_catalog_screen.dart';
import 'coach_availability_screen.dart';

// =========================================================
// 1. MyPageScreen (마이페이지 메인 화면)
// =========================================================
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _handleLogout() async {
    await AuthService().signOut();
    if (mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => const LoginScreen()));
    }
  }

  Future<void> _openSignatureBadgeCatalog() async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    var sport = '';
    try {
      final instructor = await FirebaseFirestore.instance
          .collection('instructors')
          .doc(uid)
          .get();
      final value = instructor.data()?['sport'];
      if (value is String) sport = value.trim();
    } catch (_) {
      // The catalog remains usable offline; unknown sports use a neutral medal.
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureBadgeCatalogScreen(sport: sport),
      ),
    );
  }

  // Base64 문자열 또는 URL 이미지 표시 헬퍼 함수
  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0F12),
        body: Center(
            child: Text('로그인이 필요합니다.', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        title: const Text('마이페이지',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D0F12),
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70),
              tooltip: '로그아웃',
              onPressed: _handleLogout),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
                child: Text('사용자 정보를 찾을 수 없습니다.',
                    style: TextStyle(color: Colors.white)));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final String name = userData['name'] ?? '사용자';
          final String email = userData['email'] ?? currentUser!.email ?? '';
          final String? profileImage =
              userData['profileImage'] ?? userData['photoUrl'];
          final String targetTier = userData['targetTier'] ?? '비기너';
          final int lessonCount = userData['lessonCount'] ?? 0;
          final String aspirations =
              userData['aspirations'] ?? userData['bio'] ?? '등록된 포부가 없습니다.';
          final String videoUrl = userData['videoUrl'] ?? '등록된 영상이 없습니다.';

          final String role = userData['role'] ?? 'student';
          final tier = TierCalculator.calculateTierInfo(
            lessonCount: (userData['lessonCount'] as num?)?.toInt() ?? 0,
            reviewScores: (userData['reviewScores'] as List<dynamic>? ?? [])
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(),
            teacherMatchCount:
                (userData['teacherMatchCount'] as num?)?.toInt() ?? 0,
            feedLikeCount: (userData['feedLikeCount'] as num?)?.toInt() ?? 0,
          );
          final bool isAdmin = (role == 'admin');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 프로필 상단 카드
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1C29),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // 프로필 사진 네모 아바타
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ProfilePhoto(image: profileImage ?? ''),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAdmin
                                            ? const Color(0xFF38BDF8)
                                                .withValues(alpha: 0.2)
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isAdmin
                                            ? '관리자'
                                            : (role == 'coach' ? '코치' : '수강생'),
                                        style: TextStyle(
                                          color: isAdmin
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white70,
                                          fontSize: 11,
                                          fontWeight: isAdmin
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(email,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 13)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text('현재 티어: ${tier.tierName}',
                                        style: const TextStyle(
                                            color: Color(0xFF38BDF8),
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                    if (tier.isGeneralMember) ...[
                                      const SizedBox(width: 6),
                                      Text('($lessonCount/2회 참여)',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                    ],
                                  ],
                                ),
                                Text(
                                    '목표 티어: $targetTier · EXP ${tier.totalExp}',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final isUpdated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SignupScreen(
                                      role: userData['role'] as String? ??
                                          'student',
                                      isEditing: true,
                                      initialData: userData)),
                            );

                            if (isUpdated == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('프로필 정보가 수정되었습니다!'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('프로필 및 정보 수정하기',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (role == 'student') ...[
                  Material(
                    color: const Color(0xFF101A2C),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const ValueKey('student-signature-badge-collection'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LessonBadgesScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.workspace_premium_rounded,
                                color: Color(0xFFC6FF00), size: 30),
                            const SizedBox(height: 12),
                            const Text('나의 시그니처 뱃지 컬렉션',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                                '코치가 참여를 확인한 레슨마다 시그니처 뱃지를 모아 관리할 수 있어요.',
                                style: TextStyle(
                                    color: Color(0xFFABB5C8),
                                    fontSize: 13,
                                    height: 1.5)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('내 컬렉션 보기',
                                      style: TextStyle(
                                          color: Color(0xFFC6FF00),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: const Color(0xFFC6FF00)
                                        .withValues(alpha: .8)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (role == 'coach') ...[
                  Material(
                    color: const Color(0xFF101A2C),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const ValueKey('coach-availability-management'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CoachAvailabilityScreen(),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.event_available_rounded,
                                color: Color(0xFF10B981), size: 30),
                            SizedBox(height: 12),
                            Text('레슨 가능 날짜·시간 관리',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 8),
                            Text(
                                '수강생이 신청할 수 있는 한국 시간 기준 일정을 여러 개 등록하고 수정할 수 있어요.',
                                style: TextStyle(
                                    color: Color(0xFFABB5C8),
                                    fontSize: 13,
                                    height: 1.5)),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('가능 시간 관리하기',
                                      style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: Color(0xFF10B981)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: const Color(0xFF101A2C),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const ValueKey('coach-signature-badge-management'),
                      onTap: _openSignatureBadgeCatalog,
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Color(0xFF38BDF8), size: 30),
                            SizedBox(height: 12),
                            Text('시그니처 뱃지 등록·관리',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 8),
                            Text('모든 코치가 공유하는 뱃지를 선택하거나 한 단어로 새로 만들 수 있어요.',
                                style: TextStyle(
                                    color: Color(0xFFABB5C8),
                                    fontSize: 13,
                                    height: 1.5)),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('공유 뱃지 관리하기',
                                      style: TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: Color(0xFF38BDF8)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PaymentHistoryScreen(
                                adminMode: isAdmin,
                                coachMode: role == 'coach'))),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(isAdmin
                        ? '결제 관리'
                        : role == 'coach'
                            ? '정산 예정 내역'
                            : '나의 결제 내역')),
                const SizedBox(height: 20),
                if (isAdmin) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1C29),
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.amber)),
                    ),
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text('관리자 대시보드로 이동',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const AdminDashboardScreen()));
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // 나의 포부 카드
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1A1C29),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('나의 포부 / 한 줄 소개',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(aspirations,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.87),
                              fontSize: 14,
                              height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 등록된 영상 주소 카드
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1A1C29),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('등록된 영상 주소',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      SelectableText(videoUrl,
                          style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 13,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
