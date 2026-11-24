import '../services/community_service.dart';
import '../widgets/member_actions.dart';
import '../config/onepoint_design.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import '../services/auth_service.dart';
import '../widgets/profile_photo.dart';
import '../widgets/logout_confirmation.dart';

class ProfileScreen extends StatefulWidget {
  final String? targetUserId; // null이면 내 프로필, 값이 있으면 해당 유저 프로필

  const ProfileScreen({super.key, this.targetUserId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _signingOut = false;

  late bool _isMyProfile;
  late String _profileUid;

  @override
  void initState() {
    super.initState();
    _isMyProfile =
        widget.targetUserId == null || widget.targetUserId == currentUser?.uid;
    _profileUid = widget.targetUserId ?? currentUser?.uid ?? '';

    if (_profileUid.isNotEmpty) {
      _loadUserData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  // Firestore에서 실시간 유저 정보 로드
  Future<void> _loadUserData() async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection(_isMyProfile ? 'users' : 'public_users')
          .doc(_profileUid)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _userData = doc.data() as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('유저 데이터 로드 에러: $e');
      setState(() => _isLoading = false);
    }
  }

  // 로그아웃
  Future<void> _handleLogout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      if (!await confirmLogout(context) || !mounted) return;
      await AuthService().signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그아웃하지 못했습니다. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0F12),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
      );
    }

    if (_userData == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0F12),
        body: Center(
            child: Text('유저 정보를 불러올 수 없습니다.',
                style: TextStyle(color: Colors.white))),
      );
    }

    final String name = _userData?['name'] ?? '이름 없음';
    final String photoUrl =
        _userData?['profileImage'] ?? _userData?['photoUrl'] ?? '';
    final String bio =
        _userData?['aspirations'] ?? _userData?['bio'] ?? '등록된 한 줄 소개가 없습니다.';
    final String role = _userData?['role'] == 'coach' ? '전문 코치' : '수강생';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isMyProfile ? '내 프로필' : '$name 님의 프로필',
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          // 내 프로필인 경우: 로그아웃 버튼
          if (_isMyProfile)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white54),
              tooltip: '로그아웃',
              onPressed: _signingOut ? null : _handleLogout,
            )
          // 상대방 프로필인 경우: 상단 앱바에도 신고하기 버튼 배치
          else
            IconButton(
              icon: const Icon(Icons.report_problem_outlined,
                  color: Color(0xFFEF4444)),
              tooltip: '신고·차단',
              onPressed: () => _showReportBottomSheet(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 프로필 아바타
            Container(
              width: 100,
              height: 100,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1C29),
                shape: BoxShape.circle,
              ),
              child: ProfilePhoto(image: photoUrl),
            ),
            const SizedBox(height: 16),

            // 이름 및 역할
            Text(
              name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                role,
                style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 28),

            // 포부 / 한 줄 소개
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1C29),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('나의 포부 / 한 줄 소개',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 10),
                  Text(
                    bio,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // 버튼 처리 (내 프로필 -> 전체 화면 프로필 수정 / 타인 프로필 -> 하단 신고 바텀시트)
            if (_isMyProfile)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('프로필 수정하기',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OnepointDesign.lime,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SignupScreen(
                            role: _userData!['role'] as String? ?? 'student',
                            isEditing: true,
                            initialData: _userData!),
                      ),
                    );
                    if (updated == true && mounted) {
                      _loadUserData();
                    }
                  },
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.report_problem, size: 18),
                  label: const Text('이 신고·차단',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showReportBottomSheet(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showReportBottomSheet(BuildContext context) {
    showMemberActions(context,
        uid: _profileUid,
        name: _userData?['name'] as String? ?? '회원',
        service: CommunityService(
            firestore: _firestore, auth: FirebaseAuth.instance));
  }
}
