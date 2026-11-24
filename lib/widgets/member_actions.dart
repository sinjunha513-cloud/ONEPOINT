import 'package:flutter/material.dart';
import '../services/community_service.dart';
import '../screens/report_dialog.dart';

Future<void> showMemberActions(BuildContext context,
    {required String uid,
    required String name,
    required CommunityService service,
    String? videoId}) async {
  try {
    final blocked = await service.isBlocked(uid);
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  title:
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(videoId == null ? '회원 신고' : '영상 신고'),
                  onTap: () => Navigator.pop(context, 'report')),
              ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(blocked ? '차단 해제' : '회원 차단'),
                  onTap: () => Navigator.pop(context, 'block')),
              const SizedBox(height: 12),
            ])));
    if (!context.mounted) return;
    if (action == 'report') {
      await showDialog<void>(
          context: context,
          builder: (_) => ReportDialog(
              reportedUserId: uid,
              reportedUserName: name,
              service: service,
              targetType: videoId == null ? 'user' : 'feed',
              targetId: videoId));
      return;
    }
    if (action == 'block') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(blocked ? '차단을 해제할까요?' : '이 회원을 차단할까요?'),
                  content: Text(blocked
                      ? '이 회원의 영상과 새 활동을 다시 이용할 수 있어요.'
                      : '서로 새 레슨을 신청하거나 메시지를 보낼 수 없고, 이 회원의 영상이 숨겨져요. 진행 중인 레슨은 내 레슨에서 계속 관리할 수 있어요.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(blocked ? '차단 해제' : '차단'))
                  ]));
      if (confirmed == true) {
        await service.setBlocked(uid, !blocked);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(blocked ? '차단을 해제했습니다.' : '회원을 차단했습니다.')));
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(communityError(e))));
    }
  }
}
