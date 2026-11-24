import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../config/onepoint_design.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _busy = false;
  Map<String, dynamic>? _config;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await NotificationService.configuration();
      if (mounted) setState(() => _config = c);
    } catch (_) {
      if (mounted) setState(() => _error = '설정을 불러오지 못했습니다.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError
            ? e.message.toString()
            : '알림 설정을 저장하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('필요한 소식을 기기에서도 받아보세요', style: OnepointDesign.heading),
        const SizedBox(height: 12),
        const Text(
            '켜면 현재 기기에서 레슨·채팅 소식을 받아요. 끄면 이 계정의 기기 알림이 중지돼요. 앱 안의 알림함은 계속 이용할 수 있어요.',
            style: TextStyle(color: OnepointDesign.muted, height: 1.6)),
        const SizedBox(height: 24),
        if (!NotificationService.supported)
          const Text(
              '앱 내 브라우저에서는 기기 알림이 지원되지 않을 수 있어요. 기본 브라우저에서 열어 주세요. 아이폰·아이패드는 홈 화면에 추가한 웹앱에서 알림을 켤 수 있어요.'),
        if (_config != null)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('외부 알림 받기'),
              value: _config!['enabled'] == true,
              onChanged: _busy
                  ? null
                  : (v) => _run(v
                      ? NotificationService.enable
                      : NotificationService.disable)),
        if (_config?['enabled'] == true)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('알림 내용 미리보기'),
              subtitle: const Text('끄면 잠금 화면에 메시지 내용이 표시되지 않아요.'),
              value: _config?['previews'] != false,
              onChanged: _busy
                  ? null
                  : (v) => _run(() => NotificationService.setPreviews(v))),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.orangeAccent))),
        if (_config == null && !_busy)
          OutlinedButton(onPressed: _load, child: const Text('설정 다시 불러오기')),
        if (_config?['enabled'] == true && NotificationService.supported)
          OutlinedButton(
              onPressed: _busy ? null : () => _run(NotificationService.enable),
              child: const Text('이 기기에서 알림 연결하기')),
      ]));
}
