import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/instructor_service.dart';
import 'admin_member_detail_screen.dart';
import 'payment_history_screen.dart';
import '../services/admin_account_service.dart';
import '../services/career_pdf_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.auth, this.firestore});
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final _auth = widget.auth ?? FirebaseAuth.instance;
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  late final _instructorService =
      InstructorService(auth: _auth, firestore: _db);
  final Set<String> _processingInstructors = {};
  final Set<String> _processingUsers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, session) {
        if (session.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (session.hasError || session.data == null) {
          return const Scaffold(body: Center(child: Text('관리자 로그인이 필요합니다.')));
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').doc(session.data!.uid).snapshots(),
          builder: (context, member) {
            if (member.hasError) {
              return const Scaffold(
                  body: Center(child: Text('관리자 권한을 확인하지 못했습니다.')));
            }
            if (!member.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (member.data?.data()?['role'] != 'admin') {
              return const Scaffold(
                  body: Center(child: Text('관리자만 접근할 수 있습니다.')));
            }
            return _buildDashboard(context);
          },
        );
      },
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        title: const Text('관리자 대시보드',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D0F12),
        elevation: 0,
        actions: [
          IconButton(
              tooltip: '결제 관리',
              icon: const Icon(Icons.payments_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const PaymentHistoryScreen(adminMode: true))))
        ],
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '대시보드 개요'),
            Tab(text: '코치 승인 요청'),
            Tab(text: '회원 관리'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildCoachApprovalTab(),
          _buildUserManagementTab(),
        ],
      ),
    );
  }

  // =========================================================
  // Tab 1: 대시보드 개요 (통계 요약)
  // =========================================================
  Widget _buildOverviewTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('users')
          .where('profileCompleted', isEqualTo: true)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) {
          return _buildLoadError('회원 통계', userSnapshot.error);
        }
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
        }

        final users = userSnapshot.data?.docs ?? [];
        final totalUsers = users.length;
        final coachCount = users
            .where((doc) =>
                (doc.data() as Map<String, dynamic>)['role'] == 'coach')
            .length;
        final adminCount = users
            .where((doc) =>
                (doc.data() as Map<String, dynamic>)['role'] == 'admin')
            .length;
        final studentCount = totalUsers - coachCount - adminCount;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('플랫폼 현황 요약',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _buildStatCard('전체 회원 수', '$totalUsers 명', Icons.people,
                      const Color(0xFF38BDF8)),
                  _buildStatCard('수강생 수', '$studentCount 명', Icons.school,
                      Colors.greenAccent),
                  _buildStatCard(
                      '등록된 코치', '$coachCount 명', Icons.sports, Colors.amber),
                  _buildStatCard('관리자', '$adminCount 명',
                      Icons.admin_panel_settings, Colors.purpleAccent),
                ],
              ),
              const SizedBox(height: 24),
              const Text('최근 등록 알림 및 가이드',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1C29),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💡 관리자 안내 사항',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      '• 새로 신청된 코치 프로필을 검증한 후 [코치 승인 요청] 탭에서 승인해 주세요.\n'
                      '• 코치 권한은 코치 프로필 승인 시 부여됩니다.\n'
                      '• [회원 관리] 탭에서 권한을 변경할 수 있으며, 자신의 관리자 권한은 변경할 수 없습니다.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Icon(icon, color: accentColor, size: 20),
            ],
          ),
          Text(value,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // =========================================================
  // Tab 2: 코치 승인 요청 관리
  // =========================================================
  Widget _buildCoachApprovalTab() {
    return StreamBuilder<QuerySnapshot>(
      // 승인 대기 중(pending) 상태인 코치 신청서 조회
      stream: _db
          .collection('instructors')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildLoadError('코치 승인 요청', snapshot.error);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
        }

        final pendingList = snapshot.data?.docs ?? [];

        if (pendingList.isEmpty) {
          return const Center(
            child: Text('대기 중인 코치 승인 요청이 없습니다.',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pendingList.length,
          itemBuilder: (context, index) {
            final doc = pendingList[index];
            final data = doc.data() as Map<String, dynamic>;
            final isProcessing = _processingInstructors.contains(doc.id);
            final String name = data['name'] ?? '이름 없음';
            final String sport = data['sport'] ?? '미정';
            final String career = data['career'] ?? '경력 정보 없음';
            final String bio = data['bio'] ?? '소개 없음';
            final signatureMove = (data['signatureMove'] as String?)?.trim();

            return Card(
              color: const Color(0xFF1A1C29),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(sport,
                              style: const TextStyle(
                                  color: Color(0xFF38BDF8), fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('경력: $career',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Text('수업 난이도: ${data['lessonLevel'] ?? '미등록'}',
                        style: const TextStyle(
                            color: Color(0xFF38BDF8), fontSize: 13)),
                    if (data['careerPdfId'] is String)
                      TextButton.icon(
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('경력 PDF 확인'),
                          onPressed: () async {
                            try {
                              await CareerPdfService().open(context, doc.id,
                                  data['careerPdfId'] as String);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('PDF를 불러오지 못했습니다.')));
                              }
                            }
                          }),
                    const SizedBox(height: 4),
                    Text('소개: $bio',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFF38BDF8), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '시그니처 뱃지: ${signatureMove == null || signatureMove.isEmpty ? '미등록' : signatureMove}',
                            style: const TextStyle(
                                color: Color(0xFF38BDF8), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isProcessing) ...[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                        ],
                        OutlinedButton(
                          onPressed: isProcessing
                              ? null
                              : () => _reviewCoach(doc.id, approve: false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          child: const Text('거절'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isProcessing
                              ? null
                              : () => _reviewCoach(doc.id, approve: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('승인 완료',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _reviewCoach(String instructorDocId,
      {required bool approve}) async {
    if (_processingInstructors.contains(instructorDocId)) return;
    setState(() => _processingInstructors.add(instructorDocId));
    try {
      if (approve) {
        await _instructorService.approveInstructor(instructorDocId);
      } else {
        await _instructorService.rejectInstructor(instructorDocId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(approve ? '코치 승인이 완료되었습니다.' : '코치 신청이 거절되었습니다.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        final message = switch (error.code) {
          'permission-denied' => '관리자 권한을 확인하지 못했습니다. 다시 로그인해 주세요.',
          'unavailable' ||
          'network-request-failed' =>
            '서버에 연결하지 못했습니다. 인터넷 연결을 확인해 주세요.',
          'aborted' => '다른 관리자가 먼저 처리했습니다. 목록을 새로 확인해 주세요.',
          _ => '신청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) {
        setState(() => _processingInstructors.remove(instructorDocId));
      }
    }
  }

  Widget _buildLoadError(String label, Object? error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$label 정보를 불러오지 못했습니다.\n$error',
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );

  Future<void> _changeUserRole(String userId, String name, String role) async {
    if (_processingUsers.contains(userId)) return;
    setState(() => _processingUsers.add(userId));
    try {
      await _instructorService.updateUserRole(userId, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 님의 권한을 변경했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('권한 변경 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _processingUsers.remove(userId));
    }
  }

  Future<void> _manageAccount(String uid, String name, String action) async {
    if (_processingUsers.contains(uid)) return;
    final reason = TextEditingController();
    final confirmation = TextEditingController();
    final label = action == 'delete'
        ? '계정 영구 삭제'
        : action == 'restore'
            ? '정지 해제'
            : '계정 정지';
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, change) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1C29),
                  title: Text('$name · $label',
                      style: const TextStyle(color: Colors.white)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(action == 'delete'
                        ? '로그인 계정과 프로필이 삭제되어 복구할 수 없습니다. 레슨·결제 기록은 보존됩니다.'
                        : action == 'restore'
                            ? '이 회원이 다시 로그인하고 이용할 수 있습니다.'
                            : '로그인과 서비스 접근을 차단하고 코치 목록에서 숨깁니다.'),
                    TextField(
                        controller: reason,
                        maxLength: 500,
                        onChanged: (_) => change(() {}),
                        decoration: const InputDecoration(labelText: '처리 사유')),
                    if (action == 'delete')
                      TextField(
                          controller: confirmation,
                          onChanged: (_) => change(() {}),
                          decoration:
                              const InputDecoration(labelText: '확인 문구: 삭제')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('닫기')),
                    FilledButton(
                        onPressed: reason.text.trim().isNotEmpty &&
                                (action != 'delete' ||
                                    confirmation.text == '삭제')
                            ? () => Navigator.pop(context, true)
                            : null,
                        child: Text(label))
                  ],
                )));
    final explanation = reason.text.trim();
    reason.dispose();
    confirmation.dispose();
    if (approved != true || !mounted) return;
    setState(() => _processingUsers.add(uid));
    try {
      await AdminAccountService().manage(uid, action, explanation);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$name · $label 완료')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('계정 관리 실패: $error')));
      }
    } finally {
      if (mounted) setState(() => _processingUsers.remove(uid));
    }
  }

  // =========================================================
  // Tab 3: 전체 회원 관리
  // =========================================================
  Widget _buildUserManagementTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('users')
          .where('profileCompleted', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildLoadError('회원 목록', snapshot.error);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
        }

        final users = snapshot.data?.docs ?? [];
        if (users.isEmpty) {
          return const Center(
            child:
                Text('등록된 회원이 없습니다.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final doc = users[index];
            final data = doc.data() as Map<String, dynamic>;
            final String name = data['name'] ?? '이름 없음';
            final String email = data['email'] ?? '';
            final String currentRole = data['role'] ?? 'student';

            return Card(
              color: const Color(0xFF1A1C29),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AdminMemberDetailScreen(
                            uid: doc.id, auth: _auth, firestore: _db))),
                title: Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '$email${data['accountStatus'] == 'suspended' ? '\n이용 정지' : data['accountStatus'] == 'deleting' ? '\n삭제 처리 중 · 다시 삭제 실행 가능' : ''}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: _processingUsers.contains(doc.id)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButton<String>(
                          key: ValueKey('member-role-${doc.id}'),
                          value: ['student', 'coach', 'admin']
                                  .contains(currentRole)
                              ? currentRole
                              : 'student',
                          dropdownColor: const Color(0xFF1A1C29),
                          style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                          underline: Container(),
                          items: const [
                            DropdownMenuItem(
                                value: 'student', child: Text('수강생')),
                            DropdownMenuItem(value: 'coach', child: Text('코치')),
                            DropdownMenuItem(
                                value: 'admin', child: Text('관리자')),
                          ],
                          onChanged: doc.id == _auth.currentUser?.uid ||
                                  (data['accountStatus'] ?? 'active') !=
                                      'active'
                              ? null
                              : (newRole) {
                                  if (newRole != null &&
                                      newRole != currentRole) {
                                    _changeUserRole(doc.id, name, newRole);
                                  }
                                },
                        ),
                        if (doc.id != _auth.currentUser?.uid &&
                            currentRole != 'admin')
                          PopupMenuButton<String>(
                            tooltip: '계정 관리',
                            onSelected: (action) =>
                                _manageAccount(doc.id, name, action),
                            itemBuilder: (_) => [
                              if (data['accountStatus'] != 'deleting')
                                PopupMenuItem(
                                    value: data['accountStatus'] == 'suspended'
                                        ? 'restore'
                                        : 'suspend',
                                    child: Text(
                                        data['accountStatus'] == 'suspended'
                                            ? '정지 해제'
                                            : '계정 정지')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('계정 영구 삭제',
                                      style:
                                          TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                      ]),
              ),
            );
          },
        );
      },
    );
  }
}
