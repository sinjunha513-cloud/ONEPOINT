import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/community_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key, required this.service});
  final CommunityService service;
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final _stream = widget.service.blocked();
  final _busy = <String>{};
  Future<void> _unblock(String uid) async {
    setState(() => _busy.add(uid));
    try {
      await widget.service.setBlocked(uid, false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(communityError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('차단한 회원')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, s) {
            if (s.hasError) {
              return const Center(child: Text('차단 목록을 불러오지 못했습니다.'));
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.data!.docs.isEmpty) {
              return const Center(child: Text('차단한 회원이 없습니다.'));
            }
            return ListView(children: [
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                      '차단한 회원의 영상은 숨겨지고, 서로 새 레슨을 신청하거나 메시지를 보낼 수 없어요. 진행 중인 레슨은 내 레슨에서 계속 관리할 수 있어요.')),
              for (final d in s.data!.docs)
                ListTile(
                    title: Text(d.data()['name'] as String? ?? '회원'),
                    trailing: OutlinedButton(
                        onPressed:
                            _busy.contains(d.id) ? null : () => _unblock(d.id),
                        child: const Text('차단 해제')))
            ]);
          }));
}
