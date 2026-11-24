import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import 'password_reset_screen.dart';
import 'blocked_users_screen.dart';
import 'notification_settings_screen.dart';
import 'login_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen(
      {super.key,
      required this.service,
      this.functions,
      this.role = 'student'});
  final AuthService service;
  final FirebaseFunctions? functions;
  final String role;
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _busy = false;
  Future<void> _delete() async {
    final password = await showDialog<String>(
        context: context,
        builder: (_) => _WithdrawalDialog(
            passwordRequired: widget.service.currentUser?.providerData
                    .any((p) => p.providerId == 'password') ??
                false));
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.reauthenticateForAccountChange(password);
      await (widget.functions ??
              FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
          .httpsCallable('requestAccountDeletion')
          .call({'confirmation': '회원탈퇴'});
      await widget.service.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => LoginScreen(service: widget.service)),
            (_) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is FirebaseFunctionsException
                ? communityError(e)
                : '다시 인증하거나 진행 중인 레슨을 정리한 뒤 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('계정 설정')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('비밀번호 재설정'),
            onTap: _busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PasswordResetScreen(
                            service: widget.service,
                            initialEmail:
                                widget.service.currentUser?.email ?? '')))),
        ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('알림 설정'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()))),
        ListTile(
            leading: const Icon(Icons.block),
            title: const Text('차단한 회원'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BlockedUsersScreen(
                        service: CommunityService(
                            firestore: widget.service.firestore,
                            auth: widget.service.auth))))),
        const Divider(),
        if (widget.role != 'admin')
          ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: Colors.redAccent),
              title: Text(_busy ? '탈퇴 요청 중…' : '회원탈퇴',
                  style: const TextStyle(color: Colors.redAccent)),
              subtitle: const Text('계정과 직접 등록한 콘텐츠 정리를 요청합니다.'),
              onTap: _busy ? null : _delete),
        if (_busy) const LinearProgressIndicator(),
      ]));
}

class _WithdrawalDialog extends StatefulWidget {
  const _WithdrawalDialog({required this.passwordRequired});
  final bool passwordRequired;
  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final _confirmation = TextEditingController(),
      _password = TextEditingController();
  @override
  void dispose() {
    _confirmation.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('회원탈퇴'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text(
                    '탈퇴를 요청하면 계정 이용이 즉시 중지되고 로그인 계정·프로필·직접 올린 영상과 메시지를 삭제합니다. 레슨·운영 기록은 탈퇴한 회원으로 표시해 보존합니다. 대기·진행 중인 레슨은 먼저 정리해 주세요.'),
                const SizedBox(height: 16),
                TextField(
                    controller: _confirmation,
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: '회원탈퇴를 입력해 주세요')),
                if (widget.passwordRequired)
                  TextField(
                      controller: _password,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '현재 비밀번호')),
                if (!widget.passwordRequired)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Google 계정으로 한 번 더 본인 확인을 진행합니다.')),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            FilledButton(
                onPressed: _confirmation.text.trim() == '회원탈퇴' &&
                        (!widget.passwordRequired || _password.text.isNotEmpty)
                    ? () => Navigator.pop(context, _password.text)
                    : null,
                child: const Text('인증하고 탈퇴 요청'))
          ]);
}
