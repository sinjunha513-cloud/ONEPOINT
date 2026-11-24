import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../widgets/onepoint_icon.dart';
import '../widgets/member_actions.dart';
import '../services/community_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String targetName;
  final ChatService? service;
  const ChatRoomScreen(
      {super.key,
      required this.roomId,
      required this.targetName,
      this.service});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();
  late final _service = widget.service ?? ChatService();
  late final _other = _service.otherMember(widget.roomId);
  bool _sending = false;
  int _messageLimit = 50;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(widget.roomId, text);
      if (mounted && _controller.text.trim() == text) _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지를 보내지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF070101),
        appBar: AppBar(
          actions: [
            FutureBuilder<String?>(
                future: _other,
                builder: (context, s) => s.data == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '신고·차단',
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => showMemberActions(context,
                            uid: s.data!,
                            name: widget.targetName,
                            service: CommunityService(
                                firestore: _service.firestore,
                                auth: _service.auth))))
          ],
          backgroundColor: const Color(0xFF070101),
          foregroundColor: const Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 104,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              key: const ValueKey('chat-back-button'),
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide.none,
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: const Text(
                '뒤로',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          title: Text(
            '${widget.targetName} 피드백',
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Color(0xFF252525)),
          ),
        ),
        body: Column(children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.messages(widget.roomId, limit: _messageLimit),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      '메시지를 불러오지 못했습니다.',
                      style: TextStyle(color: Color(0xFFB9B9B9)),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF24A9FF),
                    ),
                  );
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      '첫 메시지를 보내 보세요.',
                      style: TextStyle(
                        color: Color(0xFFB9B9B9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      docs.length + (docs.length == _messageLimit ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == docs.length) {
                      return TextButton(
                          onPressed: () => setState(() => _messageLimit += 50),
                          child: const Text('이전 메시지 더 보기'));
                    }
                    final data = docs[index].data();
                    final mine = data['senderId'] == _service.currentUid;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF24A9FF)
                              : const Color(0xFF444444),
                          borderRadius: BorderRadius.circular(16),
                          border: mine
                              ? null
                              : Border.all(color: const Color(0xFFD0D5DD)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D101828),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          data['text'] as String? ?? '',
                          style: TextStyle(
                            color: mine ? Colors.black : Colors.white,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF070101),
              border: Border(
                top: BorderSide(color: Color(0xFF252525)),
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-message-input'),
                    controller: _controller,
                    style: const TextStyle(color: Color(0xFFFFFFFF)),
                    cursorColor: const Color(0xFF0284C7),
                    decoration: InputDecoration(
                      hintText: '메시지 입력',
                      hintStyle: const TextStyle(color: Color(0xFF949494)),
                      filled: true,
                      fillColor: const Color(0xFF252525),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                            color: Color(0xFF24A9FF), width: 2),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('chat-send-button'),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFC7F000),
                    disabledBackgroundColor: const Color(0xFF475467),
                    foregroundColor: const Color(0xFF07111F),
                    minimumSize: const Size.square(46),
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF07111F)),
                        )
                      : const OnepointIcon('send', width: 24, height: 24),
                  onPressed: _sending ? null : _send,
                ),
              ]),
            ),
          ),
        ]),
      );
}
