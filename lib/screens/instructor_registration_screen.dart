import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/instructor_service.dart';
import 'session_gate_screen.dart';
import '../config/sports.dart';
import '../services/career_pdf_service.dart';
import '../config/signature_badge_palette.dart';
import '../models/signature_badge.dart';
import 'signature_badge_catalog_screen.dart';
import 'coach_availability_screen.dart';

class InstructorRegistrationScreen extends StatefulWidget {
  const InstructorRegistrationScreen(
      {super.key, this.completeSignup = false, this.auth, this.firestore});

  final bool completeSignup;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  State<InstructorRegistrationScreen> createState() =>
      _InstructorRegistrationScreenState();
}

class _InstructorRegistrationScreenState
    extends State<InstructorRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _careerController = TextEditingController();
  final _signatureController = TextEditingController();

  String? _selectedSport = '축구';
  String? _selectedLessonLevel = coachWelcomeLevels.first;
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  bool _profileLoaded = false;
  String? _status;
  String? _loadError;
  String? _careerPdfId;
  String? _careerPdfName;
  String? _signatureBadgeId;
  int? _signatureBadgeColorIndex;
  bool _uploadingPdf = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  late final _auth = widget.auth ?? FirebaseAuth.instance;
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  late final _instructorService =
      InstructorService(auth: _auth, firestore: _db);

  @override
  void initState() {
    super.initState();
    _watchProfile();
  }

  void _watchProfile() {
    _subscription?.cancel();
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _isLoadingProfile = false;
        _loadError = '로그인 후 코치 프로필을 신청할 수 있습니다.';
      });
      return;
    }
    _subscription =
        _db.collection('instructors').doc(uid).snapshots().listen((doc) {
      if (!mounted) return;
      final data = doc.data();
      setState(() {
        _status = data?['status'] as String?;
        if (!_profileLoaded && data != null) {
          _nameController.text = data['name'] as String? ?? '';
          _careerController.text = data['career'] as String? ?? '';
          _careerPdfId = data['careerPdfId'] as String?;
          _careerPdfName = _careerPdfId == null ? null : '등록된 경력 PDF';
          _signatureController.text = data['signatureMove'] as String? ?? '';
          _signatureBadgeId = data['signatureBadgeId'] as String?;
          _signatureBadgeColorIndex =
              (data['signatureBadgeColorIndex'] as num?)?.toInt();
          final sport = data['sport'];
          _selectedSport =
              supportedSports.contains(sport) ? sport as String : null;
          final lessonLevel = data['lessonLevel'];
          _selectedLessonLevel = coachWelcomeLevels.contains(lessonLevel)
              ? lessonLevel as String
              : coachWelcomeLevels.first;
        }
        _profileLoaded = true;
        _isLoadingProfile = false;
        _loadError = null;
      });
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError = '신청 정보를 불러오지 못했습니다. $error';
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _nameController.dispose();
    _careerController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_isLoading || _uploadingPdf) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _instructorService.registerInstructor(
        name: _nameController.text.trim(),
        sport: _selectedSport!,
        career: _careerController.text.trim(),
        lessonLevel: _selectedLessonLevel!,
        careerPdfId: _careerPdfId,
        rating: '0.0',
        signatureMove: _signatureController.text.trim(),
        signatureBadgeId: _signatureBadgeId,
        signatureBadgeColorIndex: _signatureBadgeColorIndex,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코치 승인 요청을 보냈습니다. 승인 후 코치 목록에 표시됩니다.')),
      );
      if (widget.completeSignup) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const SessionGateScreen()),
            (route) => false);
      } else {
        setState(() => _status = 'pending');
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_firebaseSubmitMessage(error))),
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? '입력 내용을 확인해 주세요.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('승인 요청을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _firebaseSubmitMessage(FirebaseException error) =>
      switch (error.code) {
        'permission-denied' => '승인 요청 권한을 확인하지 못했습니다. 다시 로그인한 뒤 시도해 주세요.',
        'unavailable' ||
        'network-request-failed' =>
          '서버에 연결하지 못했습니다. 인터넷 연결을 확인해 주세요.',
        'failed-precondition' => '회원가입 프로필을 먼저 완료해 주세요.',
        'unauthenticated' => '로그인 후 코치 승인을 요청해 주세요.',
        _ => '승인 요청을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.',
      };

  Future<void> _uploadPdf() async {
    if (_isLoading || _uploadingPdf) return;
    setState(() => _uploadingPdf = true);
    try {
      final file = await CareerPdfService().pickAndUpload();
      if (mounted && file != null) {
        setState(() {
          _careerPdfId = file['fileId'] as String;
          _careerPdfName = file['fileName'] as String;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message.toString()
                : 'PDF 업로드·검증을 완료하지 못했습니다. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  Future<void> _pickSignatureBadge() async {
    if (_isLoading) return;
    final result = await Navigator.push<SignatureBadgePickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureBadgeCatalogScreen(
          selectionMode: true,
          initialBadgeId: _signatureBadgeId,
          sport: _selectedSport ?? '',
          auth: _auth,
          firestore: _db,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _signatureController.text = result.badge.name;
      _signatureBadgeId = result.badge.id;
      _signatureBadgeColorIndex = result.badge.colorIndex;
    });
    final message = result.duplicateCreation
        ? '이미 등록된 ${result.badge.name} 뱃지를 선택했습니다.'
        : result.created
            ? '${result.badge.name} 뱃지를 전역 목록에 새로 등록했습니다.'
            : '${result.badge.name} 뱃지를 선택했습니다.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('코치 프로필 승인 신청'),
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        TextButton(
                          onPressed: () {
                            setState(() => _isLoadingProfile = true);
                            _watchProfile();
                          },
                          child: const Text('다시 불러오기'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '원포인트 레슨 코치로 등록하세요',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '관리자 승인 후 수강생에게 프로필이 공개됩니다. 승인된 프로필도 수정 제출하면 재심사 동안 목록에서 숨겨집니다.',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        if (_status != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(switch (_status) {
                              'pending' => '승인 대기 중입니다. 내용을 수정해 다시 제출할 수 있습니다.',
                              'approved' => '승인된 코치 프로필입니다.',
                              'rejected' =>
                                '신청이 거절되었거나 코치 권한이 변경되었습니다. 내용을 확인하고 다시 신청해 주세요.',
                              _ => '프로필을 다시 제출하여 승인을 요청해 주세요.',
                            }),
                          ),
                        ],
                        if (_status == 'approved') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CoachAvailabilityScreen(),
                                ),
                              ),
                              icon: const Icon(Icons.event_available_rounded),
                              label: const Text('레슨 가능 날짜·시간 관리'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // 1. 이름 입력
                        TextFormField(
                          enabled: !_isLoading,
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '코치 이름 (또는 닉네임)',
                            hintText: '예: 손흥민',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '이름을 입력해 주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // 2. 종목 선택 (Dropdown)
                        DropdownButtonFormField<String>(
                          key: const ValueKey('coach-sport'),
                          initialValue: _selectedSport,
                          hint: const Text('종목을 선택해 주세요.'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                          dropdownColor: const Color(0xFF1A1C29),
                          selectedItemBuilder: (_) => [
                            for (final sport in supportedSports)
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(sport,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 16)))
                          ],
                          validator: (value) => supportedSports.contains(value)
                              ? null
                              : '종목을 선택해 주세요.',
                          decoration: const InputDecoration(
                            labelText: '주요 종목',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sports),
                          ),
                          items: [
                            for (final sport in supportedSports)
                              DropdownMenuItem(
                                  value: sport, child: Text(sport)),
                          ],
                          onChanged: _isLoading
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _selectedSport = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          key: const ValueKey('coach-lesson-level'),
                          initialValue: _selectedLessonLevel,
                          hint: const Text('수업 난이도를 선택해 주세요.'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                          dropdownColor: const Color(0xFF1A1C29),
                          decoration: const InputDecoration(
                            labelText: '수업 대상 난이도',
                            helperText: '코치 목록과 상세 프로필에 표시됩니다.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.stairs_rounded),
                          ),
                          items: [
                            for (final level in coachWelcomeLevels)
                              DropdownMenuItem(
                                  value: level, child: Text(level)),
                          ],
                          validator: (value) =>
                              coachWelcomeLevels.contains(value)
                                  ? null
                                  : '수업 난이도를 선택해 주세요.',
                          onChanged: _isLoading
                              ? null
                              : (value) =>
                                  setState(() => _selectedLessonLevel = value),
                        ),
                        const SizedBox(height: 16),

                        // 3. 경력/이력 소개
                        TextFormField(
                          enabled: !_isLoading,
                          controller: _careerController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: '경력 및 대표 이력',
                            hintText:
                                '예: 전 프로선수 / KFA 지도자 자격증 보유 / 개인 레슨 경력 3년',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 60),
                              child: Icon(Icons.workspace_premium),
                            ),
                          ),
                          validator: (value) {
                            if ((value == null || value.trim().isEmpty) &&
                                _careerPdfId == null) {
                              return '경력 및 이력을 입력해 주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed:
                                _isLoading || _uploadingPdf ? null : _uploadPdf,
                            icon: const Icon(Icons.upload_file),
                            label: Text(_uploadingPdf
                                ? 'PDF 업로드·검증 중…'
                                : '경력 PDF 업로드 (5MB 이하)')),
                        if (_careerPdfId != null)
                          Row(children: [
                            Expanded(
                                child: Text(_careerPdfName ?? '경력 PDF 첨부 완료')),
                            IconButton(
                                tooltip: 'PDF 보기',
                                icon: const Icon(Icons.picture_as_pdf),
                                onPressed: () async {
                                  try {
                                    await CareerPdfService().open(context,
                                        _auth.currentUser!.uid, _careerPdfId!);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content:
                                                  Text('PDF를 불러오지 못했습니다.')));
                                    }
                                  }
                                }),
                            IconButton(
                                tooltip: '첨부 해제',
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(() {
                                          _careerPdfId = null;
                                          _careerPdfName = null;
                                        }),
                                icon: const Icon(Icons.close)),
                          ]),
                        const Text(
                            '경력 직접 입력 또는 PDF 제출 중 하나를 완료해 주세요. PDF는 본인과 관리자만 확인할 수 있습니다.',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        const Text(
                          '나의 시그니처 기술',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '코치님을 대표하는 기술을 정해 주세요. 레슨이 끝나고 출석을 확인할 때마다 수강생에게 이 기술 이름의 뱃지가 지급됩니다.',
                          style: TextStyle(color: Colors.grey, height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('coach-signature-badge'),
                          readOnly: true,
                          onTap: _isLoading ? null : _pickSignatureBadge,
                          controller: _signatureController,
                          decoration: const InputDecoration(
                            labelText: '시그니처 뱃지',
                            hintText: '공유 뱃지에서 선택하거나 새로 만드세요.',
                            helperText: '기술 이름은 공백 없는 한 단어만 사용할 수 있습니다.',
                            helperMaxLines: 2,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.auto_awesome),
                            suffixIcon: Icon(Icons.chevron_right_rounded),
                          ),
                          validator: (value) {
                            final signature = value?.trim() ?? '';
                            if (_signatureBadgeId == null ||
                                _signatureBadgeColorIndex == null) {
                              return '전역 목록에서 시그니처 뱃지를 선택해 주세요.';
                            }
                            return signatureBadgeNameError(signature);
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey('open-signature-badge-catalog'),
                            onPressed: _isLoading ? null : _pickSignatureBadge,
                            icon: const Icon(Icons.grid_view_rounded),
                            label: Text(_signatureBadgeId == null
                                ? '공유 뱃지 선택 · 새로 만들기'
                                : '다른 시그니처 뱃지 선택하기'),
                          ),
                        ),
                        _buildSignatureBadgePreview(),
                        const SizedBox(height: 28),

                        // 등록 버튼
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isLoading ? null : _submitForm,
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : Text(
                                    _status == null
                                        ? '코치 승인 요청하기'
                                        : '수정 후 승인 다시 요청하기',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSignatureBadgePreview() {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_nameController, _signatureController]),
      builder: (context, child) {
        final signature = _signatureController.text.trim();
        final instructor = _nameController.text.trim();
        final badgeColor = _signatureBadgeId == null
            ? colors.primary
            : signatureBadgeColor(_signatureBadgeColorIndex,
                legacyIdentity: _signatureBadgeId!);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.workspace_premium_rounded,
                    color: badgeColor, size: 38),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('출석 인증 뱃지 미리보기',
                        style: TextStyle(color: badgeColor, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(signature.isEmpty ? '나만의 시그니처 기술' : signature,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('${instructor.isEmpty ? '코치' : instructor}의 레슨 참여 인증',
                        style: TextStyle(
                            color: colors.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
