import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_notification.dart';

class NotificationInboxService {
  NotificationInboxService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseFunctions? functions})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        _functions = functions;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseFunctions? _functions;
  String get currentUid =>
      auth.currentUser?.uid ?? (throw StateError('로그인이 필요합니다.'));
  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      firestore.collection('users').doc(uid).collection('notifications');
  Stream<List<AppNotification>> watch({int limit = 50}) =>
      _collection(currentUid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(AppNotification.fromDocument).toList());
  Future<void> markRead(String id) => _collection(currentUid)
      .doc(id)
      .update({'readAt': FieldValue.serverTimestamp()});
  Future<void> markAllRead() async {
    final uid = currentUid;
    while (true) {
      if (currentUid != uid) throw StateError('로그인 계정이 변경되었습니다.');
      final unread =
          await _collection(uid).where('readAt', isNull: true).limit(400).get();
      if (unread.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    }
  }

  Future<void> syncExisting() async {
    final uid = currentUid;
    final api =
        _functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    for (final category in ['lessons', 'chats', 'profile']) {
      String? cursor;
      do {
        if (currentUid != uid) throw StateError('로그인 계정이 변경되었습니다.');
        final result = await api
            .httpsCallable('syncMyNotifications')
            .call({'category': category, if (cursor != null) 'cursor': cursor});
        cursor = (result.data as Map)['cursor'] as String?;
      } while (cursor != null);
    }
  }
}
