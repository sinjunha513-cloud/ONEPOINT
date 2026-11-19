import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';
import '../widgets/onepoint_app_bar.dart';
import '../widgets/onepoint_icon.dart';
import '../config/onepoint_design.dart';
import 'main_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, this.service, this.onFindCoach});

  final ChatService? service;
  final VoidCallback? onFindCoach;

  @override
  Widget build(BuildContext context) {
    final service = this.service ?? ChatService();
    return Scaffold(
      backgroundColor: const Color(0xFF070101),
      appBar: const OnepointAppBar(title: '1:1 피드백 채팅'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.rooms(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                '채팅 목록을 불러오지 못했습니다.',
                style: TextStyle(color: Color(0xFFB9B9B9)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF24A9FF)),
            );
          }
          final rooms = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final aTime = a.data()['updatedAt'] as Timestamp?;
              final bTime = b.data()['updatedAt'] as Timestamp?;
              return (bTime?.millisecondsSinceEpoch ?? 0)
                  .compareTo(aTime?.millisecondsSinceEpoch ?? 0);
            });
          if (rooms.isEmpty) {
            return Center(
                child: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const OnepointIcon('chat-empty', width: 53, height: 53),
                const SizedBox(height: 18),
                const Text('아직 채팅방이 없어요', style: OnepointDesign.heading),
                const SizedBox(height: 10),
                const Text('코치가 레슨을 수락하면\n이곳에서 1:1 채팅을 시작할 수 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: OnepointDesign.muted)),
                const SizedBox(height: 26),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: OnepointDesign.lime,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 18)),
                  onPressed: onFindCoach ??
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MainScreen())),
                  child: const Text('코치 찾아보기'),
                ),
              ]),
            )));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final data = room.data();
              final isStudent = data['studentUid'] == service.currentUid;
              final name = (isStudent ? data['coachName'] : data['studentName'])
                      as String? ??
                  '상대방';
              return Card(
                color: OnepointDesign.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF373737)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.person, color: Color(0xFF24A9FF)),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    data['lastMessage'] as String? ?? '대화를 시작해 보세요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF949494)),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF949494),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatRoomScreen(roomId: room.id, targetName: name),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
