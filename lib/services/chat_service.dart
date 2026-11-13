import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return uid;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> rooms() => _db
      .collection('chat_rooms')
      .where('participantIds', arrayContains: currentUid)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String roomId) => _db
      .collection('chat_rooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .snapshots();

  Future<void> sendMessage(String roomId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final room = _db.collection('chat_rooms').doc(roomId);
    final snapshot = await room.get();
    if (!snapshot.exists ||
        !(List<String>.from(snapshot.data()?['participantIds'] ?? [])
            .contains(currentUid))) {
      throw StateError('참여할 수 없는 채팅방입니다.');
    }
    final batch = _db.batch();
    batch.set(room.collection('messages').doc(), {
      'senderId': currentUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(room, {
      'lastMessage': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
