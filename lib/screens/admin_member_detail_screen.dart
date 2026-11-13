import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/profile_photo.dart';
import '../services/career_pdf_service.dart';

/// Displays an explicit field allowlist; tokens and unknown fields are omitted.
class AdminMemberDetailScreen extends StatelessWidget {
  const AdminMemberDetailScreen(
      {super.key, required this.uid, this.auth, this.firestore});
  final String uid;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  static String displayValue(dynamic value) {
    if (value == null || value == '') return '정보 없음';
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (value is List) return value.isEmpty ? '정보 없음' : value.join(', ');
    return value.toString();
  }

  Widget _section(String title, Map<String, dynamic> values) => Card(
        color: const Color(0xFF1A1C29),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final entry in values.entries)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: SelectableText(
                      '${entry.key}: ${displayValue(entry.value)}',
                      style: const TextStyle(color: Colors.white70))),
          ]),
        ),
      );

  Widget _message(String text) =>
      Center(child: Text(text, style: const TextStyle(color: Colors.white70)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0D0F12),
        appBar: AppBar(
            title: const Text('회원 상세정보'),
            backgroundColor: const Color(0xFF0D0F12)),
        body: StreamBuilder<User?>(
          stream: (auth ?? FirebaseAuth.instance).authStateChanges(),
          builder: (context, session) {
            if (session.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (session.hasError || session.data == null) {
              return _message('관리자 로그인이 필요합니다.');
            }
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: (firestore ?? FirebaseFirestore.instance)
                  .collection('users')
                  .doc(session.data!.uid)
                  .snapshots(),
              builder: (context, admin) {
                if (admin.hasError) return _message('관리자 권한을 확인하지 못했습니다.');
                if (!admin.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (admin.data?.data()?['role'] != 'admin') {
                  return _message('관리자만 조회할 수 있습니다.');
                }
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: (firestore ?? FirebaseFirestore.instance)
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _message('회원 정보를 불러오지 못했습니다.');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snapshot.data!.data();
                    if (data == null) return _message('회원 정보를 찾을 수 없습니다.');
                    final role = data['role'];
                    final requested = data['requestedRole'];
                    return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SizedBox(
                              height: 120,
                              child: ProfilePhoto(
                                  image: data['profileImage'] as String? ??
                                      data['photoUrl'] as String? ??
                                      '')),
                          _section('기본 정보', {
                            '이름 / 닉네임': data['name'],
                            '이메일': data['email'],
                            'UID': uid,
                            '가입일': data['createdAt'],
                            '최근 수정일': data['updatedAt'],
                          }),
                          _section('계정 상태', {
                            '이용약관 동의':
                                data['termsAccepted'] == true ? '동의' : '미확인',
                            '개인정보 수집·이용 동의':
                                data['privacyAccepted'] == true ? '동의' : '미확인',
                            '동의 문서 버전': data['consentVersion'],
                            '동의일': data['consentedAt'],
                            '현재 권한': switch (role) {
                              'admin' => '관리자',
                              'coach' => '코치',
                              'student' => '수강생',
                              _ => '미확인'
                            },
                            '선택한 가입 유형': requested == 'coach'
                                ? '코치'
                                : requested == 'student'
                                    ? '수강생'
                                    : '미확인',
                            '가입 상태': switch (data['profileCompleted']) {
                              true => '가입 완료',
                              false => '가입 미완료',
                              _ => '미확인 (기존 회원 데이터)'
                            },
                          }),
                          _section('프로필', {
                            '현재 티어': data['currentTier'],
                            '목표 티어': data['targetTier'],
                            '플레이 스타일': data['playStyle'],
                            '관심 태그': data['tags'],
                            '소개': data['aspirations'] ?? data['bio'],
                            '소개 / 연습 영상': data['videoUrl'],
                            '시그니처 기술': data['signatureMove'],
                          }),
                          _section('활동 정보 (저장된 집계)', {
                            '완료 레슨 수': data['lessonCount'],
                            '리뷰 점수': data['reviewScores'],
                            '코치 매칭 수': data['teacherMatchCount'],
                            '받은 피드 좋아요': data['feedLikeCount'],
                          }),
                          if (role == 'coach' || requested == 'coach')
                            StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>>(
                              stream: (firestore ?? FirebaseFirestore.instance)
                                  .collection('instructors')
                                  .doc(uid)
                                  .snapshots(),
                              builder: (context, instructor) {
                                if (instructor.hasError) {
                                  return _section(
                                      '코치 정보', {'조회 상태': '불러오지 못했습니다.'});
                                }
                                if (!instructor.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                final coach = instructor.data?.data();
                                if (coach == null) {
                                  return _section(
                                      '코치 정보', {'신청 상태': '등록된 신청 정보 없음'});
                                }
                                return Column(children: [
                                  _section('코치 정보', {
                                    '승인 상태': switch (coach['status']) {
                                      'pending' => '승인 대기',
                                      'approved' => '승인 완료',
                                      'rejected' => '승인 거절',
                                      _ => '미확인'
                                    },
                                    '코치 이름': coach['name'],
                                    '전문 종목': coach['sport'],
                                    '수업 난이도': coach['lessonLevel'],
                                    '경력': coach['career'],
                                    '시그니처 기술': coach['signatureMove'],
                                    '평점': coach['rating'],
                                    '등록일': coach['createdAt'],
                                    '신청일': coach['submittedAt'],
                                    '승인일': coach['approvedAt'],
                                  }),
                                  if (coach['careerPdfId'] is String)
                                    TextButton.icon(
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: const Text('경력 PDF 보기'),
                                        onPressed: () async {
                                          try {
                                            await CareerPdfService().open(
                                                context,
                                                uid,
                                                coach['careerPdfId'] as String);
                                          } catch (_) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'PDF를 불러오지 못했습니다.')));
                                            }
                                          }
                                        })
                                ]);
                              },
                            ),
                        ]);
                  },
                );
              },
            );
          },
        ),
      );
}
