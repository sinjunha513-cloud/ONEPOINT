import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_profile_service.dart';
import '../models/signup_consent.dart';
import '../widgets/profile_photo.dart';
import 'instructor_registration_screen.dart';
import 'session_gate_screen.dart';

/// Registration, Google onboarding and editing share the same profile fields.
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.role,
    this.isEditing = false,
    this.completeProfile = false,
    this.initialData,
    this.auth,
    this.firestore,
  }) : assert(!isEditing || !completeProfile);

  final String role;
  final bool isEditing;
  final bool completeProfile;
  final Map<String, dynamic>? initialData;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _profileImageController = TextEditingController();
  final _aspirationsController = TextEditingController();
  final _videoUrlController = TextEditingController();
  // Opening a new registration form does not access Firebase.
  late final _profiles =
      UserProfileService(auth: widget.auth, firestore: widget.firestore);
  static const _tiers = [
    '비기너',
    '아마추어 3',
    '아마추어 2',
    '아마추어 1',
    '세미프로 3',
    '세미프로 2',
    '세미프로 1',
    '프로 3',
    '프로 2',
    '프로 1',
    '챌린저',
  ];

  String _selectedTier = '비기너';
  String _profileImage = '';
  bool _isLoading = false;
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _isLoadingProfile = false;
  bool _profileLoadFailed = false;
  late final User? _profileUser;
  late final String? _expectedUid;
  bool get _existingAccount => widget.isEditing || widget.completeProfile;

  @override
  void initState() {
    super.initState();
    // Keep an existing-account form tied to the user who opened it.
    _profileUser = _existingAccount
        ? (widget.auth ?? FirebaseAuth.instance).currentUser
        : null;
    _expectedUid = _profileUser?.uid;
    _fillProfile(widget.initialData ?? {});
    if (_existingAccount && widget.initialData == null) {
      _loadProfile();
    }
  }

  void _fillProfile(Map<String, dynamic> stored) {
    final user = _profileUser;
    final data = <String, dynamic>{
      'name': user?.displayName ?? '',
      'profileImage': user?.photoURL ?? '',
      ...stored,
    };
    // Old profiles used photoUrl/bio. Prefer these over auth defaults.
    if (!stored.containsKey('profileImage') && stored.containsKey('photoUrl')) {
      data['profileImage'] = stored['photoUrl'];
    }
    final profile = UserProfileDraft.fromMap(data);
    _emailController.text = user?.email ?? stored['email'] as String? ?? '';
    _nameController.text = profile.name;
    _profileImage = profile.profileImage;
    _profileImageController.text = _profileImage.startsWith('http://') ||
            _profileImage.startsWith('https://')
        ? _profileImage
        : '';
    _selectedTier = profile.targetTier;
    _aspirationsController.text = profile.aspirations;
    _videoUrlController.text = profile.videoUrl;
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileLoadFailed = false;
    });
    try {
      final uid = _requireProfileUid();
      final snapshot = await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      _requireProfileUid();
      _fillProfile(snapshot.data() ?? {});
    } catch (_) {
      if (mounted) _profileLoadFailed = true;
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  String _requireProfileUid() {
    final expectedUid = _expectedUid;
    if (expectedUid == null ||
        (widget.auth ?? FirebaseAuth.instance).currentUser?.uid !=
            expectedUid) {
      throw StateError('로그인 계정이 변경되었습니다. 프로필 화면을 다시 열어 주세요.');
    }
    return expectedUid;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _profileImageController.dispose();
    _aspirationsController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 60,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 600 * 1024) {
        _showMessage('사진 용량이 큽니다. 더 작은 사진을 선택해 주세요.');
        return;
      }
      setState(() {
        _profileImageController.clear();
        _profileImage = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      });
    } catch (_) {
      if (mounted) _showMessage('사진을 불러오지 못했습니다. 다시 선택해 주세요.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_isLoading) return;
    if (!widget.isEditing && (!_termsAccepted || !_privacyAccepted)) {
      _showMessage('이용약관과 개인정보 수집·이용에 동의해 주세요.');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _showMessage('이름 / 닉네임을 입력해 주세요.');
      return;
    }
    if (!_existingAccount &&
        (_emailController.text.trim().isEmpty ||
            _passwordController.text.isEmpty)) {
      _showMessage('이메일과 비밀번호를 입력해 주세요.');
      return;
    }
    setState(() => _isLoading = true);
    final draft = UserProfileDraft(
      name: _nameController.text,
      profileImage: _profileImage,
      targetTier: _selectedTier,
      aspirations: _aspirationsController.text,
      videoUrl: _videoUrlController.text,
    );
    try {
      if (widget.isEditing) {
        await _profiles.saveProfile(draft, expectedUid: _requireProfileUid());
      } else if (widget.completeProfile) {
        await _profiles.completeProfile(
            consent: SignupConsent(
                termsAccepted: _termsAccepted,
                privacyAccepted: _privacyAccepted),
            profile: draft,
            requestedRole: widget.role,
            expectedUid: _requireProfileUid());
      } else {
        await _profiles.createAccount(
          consent: SignupConsent(
              termsAccepted: _termsAccepted, privacyAccepted: _privacyAccepted),
          email: _emailController.text,
          password: _passwordController.text,
          requestedRole: widget.role,
          profile: draft,
        );
      }
      if (!mounted) return;
      if (_existingAccount) _requireProfileUid();
      if (widget.isEditing) {
        Navigator.pop(context, true);
        return;
      }
      if (widget.role == 'coach') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => InstructorRegistrationScreen(
              completeSignup: true,
              auth: widget.auth,
              firestore: widget.firestore,
            ),
          ),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SessionGateScreen()),
          (route) => false,
        );
      }
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(switch (error.code) {
        'weak-password' => '비밀번호를 6자리 이상으로 입력해 주세요.',
        'email-already-in-use' => '이미 가입된 이메일입니다. 로그인해 주세요.',
        'invalid-email' => '올바른 이메일 주소를 입력해 주세요.',
        'network-request-failed' => '인터넷 연결을 확인하고 다시 시도해 주세요.',
        _ => '계정을 만들지 못했습니다. 잠시 후 다시 시도해 주세요.',
      });
    } catch (_) {
      if (mounted) _showMessage('프로필을 저장하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleText = widget.role == 'coach' ? '전문 코치' : '수강생';
    final title = widget.isEditing
        ? '프로필 및 정보 수정'
        : widget.completeProfile
            ? '$roleText 프로필 등록'
            : '$roleText 회원가입';
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F12),
        elevation: 0,
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : _profileLoadFailed
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('프로필을 불러오지 못했습니다.',
                      style: TextStyle(color: Colors.white)),
                  TextButton(
                      onPressed: _loadProfile, child: const Text('다시 시도')),
                ]))
              : SafeArea(
                  child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                            child: Column(children: [
                          Container(
                            width: 120,
                            height: 120,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1C29),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFF38BDF8), width: 1.5),
                            ),
                            child: ProfilePhoto(image: _profileImage),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _isLoading ? null : _pickProfileImage,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('갤러리에서 사진 선택'),
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8)),
                          ),
                          if (_profileImage.isNotEmpty)
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(() {
                                        _profileImage = '';
                                        _profileImageController.clear();
                                      }),
                              child: const Text('사진 삭제',
                                  style: TextStyle(color: Colors.white54)),
                            ),
                          const Text('사진을 선택하거나 아래에 이미지 URL을 입력해 주세요.',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ])),
                        const SizedBox(height: 32),
                        _sectionTitle('계정 정보'),
                        const SizedBox(height: 16),
                        _input('이메일 (필수)', 'profile-email', _emailController,
                            hint: 'example@email.com',
                            readOnly: _existingAccount),
                        if (!_existingAccount) ...[
                          const SizedBox(height: 16),
                          _input('비밀번호 (필수)', 'profile-password',
                              _passwordController,
                              hint: '비밀번호 6자리 이상', isPassword: true),
                        ],
                        if (_existingAccount) ...[
                          const SizedBox(height: 6),
                          const Text('로그인에 사용하는 이메일입니다.',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                        const SizedBox(height: 32),
                        _sectionTitle('프로필 정보'),
                        const SizedBox(height: 16),
                        _input('이름 / 닉네임 (필수)', 'profile-name', _nameController,
                            hint: '홍길동'),
                        const SizedBox(height: 16),
                        _input('프로필 이미지 URL', 'profile-image',
                            _profileImageController,
                            hint: 'https://...',
                            onChanged: (value) =>
                                setState(() => _profileImage = value.trim())),
                        const SizedBox(height: 16),
                        _tierDropdown(),
                        const SizedBox(height: 16),
                        _input('나의 포부 / 한 줄 소개', 'profile-aspirations',
                            _aspirationsController,
                            hint: '나를 표현할 수 있는 한 줄 소개를 적어주세요.', maxLines: 3),
                        const SizedBox(height: 16),
                        _input('소개 / 연습 영상 URL', 'profile-video',
                            _videoUrlController,
                            hint: 'https://...'),
                        if (!widget.isEditing) ...[
                          const SizedBox(height: 24),
                          _sectionTitle('필수 동의'),
                          _consentRow(
                              '이용약관 동의 (필수)',
                              'terms-consent',
                              _termsAccepted,
                              (value) => setState(() => _termsAccepted = value),
                              SignupConsent.terms),
                          _consentRow(
                              '개인정보 수집·이용 동의 (필수)',
                              'privacy-consent',
                              _privacyAccepted,
                              (value) =>
                                  setState(() => _privacyAccepted = value),
                              SignupConsent.privacy),
                        ],
                        const SizedBox(height: 40),
                        SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              key: const ValueKey('profile-save'),
                              onPressed: _isLoading ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF38BDF8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.black)
                                  : Text(
                                      widget.isEditing
                                          ? '저장하기'
                                          : widget.role == 'coach'
                                              ? '다음: 코치 승인 요청'
                                              : '가입 완료하기',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                            )),
                      ]),
                )),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));

  Widget _consentRow(String label, String key, bool value,
          ValueChanged<bool> onChanged, String content) =>
      Row(children: [
        Checkbox(
            key: ValueKey(key),
            value: value,
            activeColor: const Color(0xFF38BDF8),
            onChanged:
                _isLoading ? null : (value) => onChanged(value ?? false)),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13))),
        TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1C29),
                      title: Text(label,
                          style: const TextStyle(color: Colors.white)),
                      content: SingleChildScrollView(
                          child: SelectableText(content,
                              style: const TextStyle(color: Colors.white70))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'))
                      ],
                    )),
            child: const Text('보기')),
      ]);

  Widget _input(String label, String key, TextEditingController controller,
      {required String hint,
      bool readOnly = false,
      bool isPassword = false,
      int maxLines = 1,
      ValueChanged<String>? onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      TextField(
        key: ValueKey(key),
        controller: controller,
        readOnly: readOnly,
        enabled: !_isLoading,
        obscureText: isPassword,
        maxLines: isPassword ? 1 : maxLines,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
          suffixIcon: readOnly
              ? const Icon(Icons.lock_outline, color: Colors.white38, size: 18)
              : null,
          filled: true,
          fillColor: const Color(0xFF1A1C29),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
        ),
      ),
    ]);
  }

  Widget _tierDropdown() {
    final tiers = [
      ..._tiers,
      if (!_tiers.contains(_selectedTier)) _selectedTier
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('목표 티어 선택',
          style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFF1A1C29),
            borderRadius: BorderRadius.circular(12)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          key: const ValueKey('profile-tier'),
          value: _selectedTier,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1C29),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          items: tiers
              .map((tier) => DropdownMenuItem(value: tier, child: Text(tier)))
              .toList(),
          onChanged: _isLoading
              ? null
              : (value) {
                  if (value != null) setState(() => _selectedTier = value);
                },
        )),
      ),
      const SizedBox(height: 6),
      const Text('목표 티어는 자유롭게 선택할 수 있으며, 현재 티어는 레슨 참여와 활동에 따라 결정됩니다.',
          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
    ]);
  }
}
