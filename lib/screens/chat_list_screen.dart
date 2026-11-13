import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ChatService();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        surfaceTintColor: Colors.white,
        title: const Text(
          '1:1 피드백 채팅',
          style: TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE4E7EC)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.rooms(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                '채팅 목록을 불러오지 못했습니다.',
                style: TextStyle(color: Color(0xFF344054)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '코치가 레슨을 수락하면 채팅방이 표시됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF344054),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
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
                color: Colors.white,
                surfaceTintColor: Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.person, color: Color(0xFF2563EB)),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF101828),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    data['lastMessage'] as String? ?? '대화를 시작해 보세요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF475467)),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF667085),
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
