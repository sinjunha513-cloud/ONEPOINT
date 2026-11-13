import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import '../services/auth_service.dart';
import '../widgets/profile_photo.dart';

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

  // 신고 제출 (reports 컬렉션에 저장)
  Future<void> _submitReport(String reason, String details) async {
    if (currentUser == null) return;

    try {
      await _firestore.collection('reports').add({
        'reporterUid': currentUser!.uid,
        'reportedUid': _profileUid,
        'reportedUserName': _userData?['name'] ?? '알 수 없음',
        'reason': reason,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('신고가 정상적으로 접수되었습니다. 운영진 검토 후 조치됩니다.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 접수 실패: $e')),
        );
      }
    }
  }

  // 로그아웃
  Future<void> _handleLogout() async {
    await AuthService().signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
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
              onPressed: _handleLogout,
            )
          // 상대방 프로필인 경우: 상단 앱바에도 신고하기 버튼 배치
          else
            IconButton(
              icon: const Icon(Icons.report_problem_outlined,
                  color: Color(0xFFEF4444)),
              tooltip: '유저 신고하기',
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
                    backgroundColor: const Color(0xFF38BDF8),
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
                  label: const Text('이 유저 신고하기',
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

  // 신고하기 하단 바텀시트 호출
  void _showReportBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _ReportBottomSheetWidget(
          onSubmit: (reason, details) {
            _submitReport(reason, details);
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// [1] 풀스크린 프로필 수정 화면
// -----------------------------------------------------------------------------
class _ReportBottomSheetWidget extends StatefulWidget {
  final Function(String reason, String details) onSubmit;

  const _ReportBottomSheetWidget({required this.onSubmit});

  @override
  State<_ReportBottomSheetWidget> createState() =>
      _ReportBottomSheetWidgetState();
}

class _ReportBottomSheetWidgetState extends State<_ReportBottomSheetWidget> {
  String _selectedReason = '부적절한 언행 및 폭언·성희롱';
  final TextEditingController _detailController = TextEditingController();

  // 대괄호/괄호 문구가 깔끔하게 정돈된 신고 사유 리스트
  final List<String> _reasons = [
    '부적절한 언행 및 폭언·성희롱',
    '과도한 신체 접촉 및 안전 수칙 위반',
    '플랫폼 외 사적 결제 및 직거래 유도',
    '노쇼 및 일방적인 시간 변경·취소',
    '허위 정보 및 신원 위조',
    '기타 직접 입력',
  ];

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '유저 신고하기',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Text(
            '신고 사유를 선택해 주세요.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // 라디오 버튼 형태의 신고 사유 선택 목록
          RadioGroup<String>(
            groupValue: _selectedReason,
            onChanged: (val) {
              if (val != null) setState(() => _selectedReason = val);
            },
            child: Column(
              children: _reasons.map((reason) {
                final isSelected = _selectedReason == reason;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0F12),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: const Color(0xFFEF4444), width: 1)
                        : null,
                  ),
                  child: RadioListTile<String>(
                    value: reason,
                    activeColor: const Color(0xFFEF4444),
                    title: Text(reason,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          const Text('상세 사유 (선택)',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _detailController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: '구체적인 정황이나 참고할 사항을 입력해 주세요.',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0D0F12),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onSubmit(_selectedReason, _detailController.text.trim());
              },
              child: const Text('신고 제출하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
