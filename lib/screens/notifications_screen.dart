import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';
import '../models/app_notification.dart';
import '../services/notification_inbox_service.dart';
import '../services/matching_service.dart';
import '../services/payment_service.dart';
import '../services/lesson_badge_service.dart';
import '../services/chat_service.dart';
import '../utils/korea_time.dart';
import '../widgets/onepoint_icon.dart';
import 'lesson_requests_screen.dart';
import 'lesson_badges_screen.dart';
import 'chat_room_screen.dart';
import 'my_page_screen.dart';
import 'admin_dashboard_screen.dart';
import 'shortform_feed_screen.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen(
      {super.key, this.service, this.initialNotificationId});
  final NotificationInboxService? service;
  final String? initialNotificationId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final _service = widget.service ?? NotificationInboxService();
  late Stream<List<AppNotification>> _stream;
  int _limit = 50;
  bool _syncing = false, _marking = false;
  String? _syncError;
  final _opening = <String>{};
  @override
  void initState() {
    super.initState();
    _stream = _service.watch(limit: _limit);
    _sync();
    if (widget.initialNotificationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
    }
  }

  Future<void> _openInitial() async {
    try {
      final doc = await _service.firestore
          .collection('users')
          .doc(_service.currentUid)
          .collection('notifications')
          .doc(widget.initialNotificationId)
          .get();
      if (doc.exists && mounted) await _open(AppNotification.fromDocument(doc));
    } catch (_) {/* A notice removed by account cleanup no longer opens. */}
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await _service.syncExisting();
    } catch (_) {
      if (mounted) setState(() => _syncError = '새 알림을 확인하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _allRead() async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      await _service.markAllRead();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('읽음 상태를 저장하지 못했습니다. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!_opening.add(n.id)) return;
    try {
      if (n.unread) await _service.markRead(n.id);
      final db = _service.firestore, auth = _service.auth;
      final Widget screen;
      switch (n.targetType) {
        case 'chat':
          screen = ChatRoomScreen(
              roomId: n.targetId,
              targetName: n.targetName,
              service: ChatService(firestore: db, auth: auth));
        case 'badge':
          screen = LessonBadgesScreen(
              service: LessonBadgeService(firestore: db, auth: auth));
        case 'profile':
          screen = MyPageScreen(firestore: db, auth: auth);
        case 'admin':
          screen = const AdminDashboardScreen();
        case 'feed':
          screen = const ShortformFeedScreen();
        default:
          screen = LessonRequestsScreen(
              service: MatchingService(firestore: db, auth: auth),
              paymentService: PaymentService(firestore: db),
              initialLessonId: n.targetId);
      }
      if (mounted) {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => screen));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('알림을 열지 못했습니다. 잠시 후 다시 시도해 주세요.')));
      }
    } finally {
      _opening.remove(n.id);
    }
  }

  String _when(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '이전 활동';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return formatKoreaDate(toKoreaTime(date));
  }

  String _category(String kind) => switch (kind) {
        'chat' => '메시지',
        'feedback' => '피드백',
        'badge' => '내 뱃지',
        'schedule' => '레슨 일정',
        'payment' => '결제',
        'coach' => '코치 등록',
        'feed' => '영상 피드',
        'system' => '안내',
        _ => '내 레슨'
      };
  String _asset(String kind) => switch (kind) {
        'chat' => 'nav-chat-idle',
        'feedback' || 'feed' => 'nav-feed-idle',
        'badge' => 'badge',
        _ => 'bell'
      };
  Widget _preview(AppNotification n) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
          color: OnepointDesign.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              key: ValueKey('notification-${n.id}'),
              onTap: () => _open(n),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 38,
                            height: 38,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: OnepointDesign.background,
                                borderRadius: BorderRadius.circular(11)),
                            child: OnepointIcon(_asset(n.kind),
                                width: 22, height: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(_category(n.kind),
                                        style: const TextStyle(
                                            color: OnepointDesign.muted,
                                            fontSize: 11))),
                                Text(_when(n.createdAt),
                                    style: const TextStyle(
                                        color: OnepointDesign.muted,
                                        fontSize: 10)),
                                if (n.unread) ...[
                                  const SizedBox(width: 7),
                                  const CircleAvatar(
                                      radius: 3,
                                      backgroundColor: OnepointDesign.blue)
                                ]
                              ]),
                              const SizedBox(height: 5),
                              Text(n.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(n.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      height: 1.45)),
                            ])),
                      ])))));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('알림'), actions: [
        IconButton(
            tooltip: '알림 설정',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()))),
        TextButton(
            onPressed: _marking ? null : _allRead,
            child: Text(_marking ? '저장 중…' : '모두 읽음')),
      ]),
      body: StreamBuilder<List<AppNotification>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('알림을 불러오지 못했습니다.'),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: () {
                      setState(() => _stream = _service.watch(limit: _limit));
                      _sync();
                    },
                    child: const Text('다시 시도'))
              ]));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: RefreshIndicator(
                        onRefresh: _sync,
                        child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (_syncing)
                                const LinearProgressIndicator(
                                    color: OnepointDesign.lime),
                              if (_syncError != null)
                                Row(children: [
                                  Expanded(
                                      child: Text(_syncError!,
                                          style: const TextStyle(
                                              color: OnepointDesign.muted))),
                                  TextButton(
                                      onPressed: _sync,
                                      child: const Text('다시 확인'))
                                ]),
                              const SizedBox(height: 12),
                              if (items.isEmpty)
                                const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 100),
                                    child: Column(children: [
                                      OnepointIcon('bell',
                                          width: 38, height: 38),
                                      SizedBox(height: 18),
                                      Text('아직 알림이 없어요',
                                          style: OnepointDesign.heading),
                                      SizedBox(height: 8),
                                      Text('레슨과 메시지의 새로운 소식을 이곳에서 확인하세요.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: OnepointDesign.muted))
                                    ])),
                              for (var i = 0; i < items.length; i++) ...[
                                if (i == 0 ||
                                    !DateUtils.isSameDay(
                                        toKoreaTime(items[i - 1].createdAt),
                                        toKoreaTime(items[i].createdAt)))
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 12, top: 8),
                                      child: Text(
                                          sameKoreaDate(items[i].createdAt,
                                                  koreaNow())
                                              ? '오늘'
                                              : items[i]
                                                          .createdAt
                                                          .millisecondsSinceEpoch ==
                                                      0
                                                  ? '이전 활동'
                                                  : formatKoreaDate(toKoreaTime(
                                                      items[i].createdAt)),
                                          style: const TextStyle(
                                              color: OnepointDesign.muted,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12))),
                                _preview(items[i])
                              ],
                              if (items.length >= _limit)
                                OutlinedButton(
                                    onPressed: () => setState(() {
                                          _limit += 50;
                                          _stream =
                                              _service.watch(limit: _limit);
                                        }),
                                    child: const Text('이전 알림 더 보기')),
                            ]))));
          }));
}
