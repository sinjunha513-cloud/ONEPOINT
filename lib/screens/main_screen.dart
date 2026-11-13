import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/lesson_service.dart';
import 'profile_screen.dart';
import 'shortform_feed_screen.dart';
import 'chat_list_screen.dart';
import 'instructor_registration_screen.dart';
import 'lesson_requests_screen.dart';
import '../config/sports.dart';
import '../config/signature_badge_palette.dart';
import '../models/lesson_slot.dart';
import 'lesson_slot_picker_screen.dart';
import 'admin_dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String selectedSport = '축구';
  final LessonService _lessonService = LessonService();

  Future<void> _openCoachRegistrationOrReview() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 코치 등록을 이용해 주세요.')),
        );
      }
      return;
    }

    try {
      final profile =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      final role = profile.data()?['role'] as String?;
      if (role == 'admin') {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        return;
      }
      if (role != 'student' && role != 'coach') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원 프로필을 완료한 뒤 코치 등록을 이용해 주세요.')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InstructorRegistrationScreen(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 권한을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('원포인트레슨'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            tooltip: '내 레슨',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LessonRequestsScreen()),
            ),
          ),
          // 1. 코치 프로필 등록 버튼
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: '코치 등록 · 승인 관리',
            onPressed: _openCoachRegistrationOrReview,
          ),
          // 2. 1:1 피드백 채팅목록 버튼
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '1:1 피드백',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListScreen(),
                ),
              );
            },
          ),
          // 3. 숏폼 피드 버튼
          IconButton(
            icon: const Icon(Icons.video_library),
            tooltip: '숏폼 피드',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShortformFeedScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final sport in supportedSports)
                    ChoiceChip(
                      avatar: Icon(sportIcon(sport)),
                      label: Text(sport),
                      selected: selectedSport == sport,
                      onSelected: (selected) {
                        if (selected) setState(() => selectedSport = sport);
                      },
                    )
                ],
              )),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  '$selectedSport 추천 코치 선택',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Firestore 실시간 코치 데이터 로딩
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _lessonService.getInstructors(selectedSport),
              builder: (context, snapshot) {
                // 1. 에러 발생 시 UI & 콘솔 로그 출력
                if (snapshot.hasError) {
                  debugPrint('🔥 Firestore 에러: ${snapshot.error}');

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            '데이터를 불러오는 중 오류가 발생했습니다.',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '네트워크 상태를 확인하시거나 잠시 후 다시 시도해 주세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 2. 로딩 중 UI
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // 3. 등록된 코치가 없는 경우 (Empty State UI)
                if (docs.isEmpty) {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              sportIcon(selectedSport),
                              size: 40,
                              color: Colors.blue.shade400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '현재 등록된 $selectedSport 코치가 없습니다.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '상단의 코치 등록(+) 버튼을 눌러 첫 코치 프로필을 추가해 보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 4. 코치 목록 리스트뷰
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final docId = docs[index].id;
                    final badgeColor = signatureBadgeColor(
                        (data['signatureBadgeColorIndex'] as num?)?.toInt(),
                        legacyIdentity:
                            data['signatureMove'] as String? ?? docId);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            sportIcon(selectedSport),
                            color: Colors.blue,
                          ),
                        ),
                        title: Text(
                            '${data['name'] ?? '코치'} (★ ${data['rating'] ?? '5.0'})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data['lessonLevel'] is String)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  data['lessonLevel'] as String,
                                  style: const TextStyle(
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Text((data['career'] as String? ?? '').isNotEmpty
                                ? data['career'] as String
                                : data['careerPdfId'] != null
                                    ? '경력 PDF 제출'
                                    : '경력 정보 없음'),
                            if ((data['signatureMove'] as String? ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '시그니처 뱃지 · ${data['signatureMove']}',
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          _showInstructorDetail(context, docId, data);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
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
                                color: Colors.white,
                              ),
                            )
                          : const Text('레슨 신청하기',
                              style: TextStyle(color: Colors.white)),
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
