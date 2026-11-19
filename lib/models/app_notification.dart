import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification(
      {required this.id,
      required this.kind,
      required this.title,
      required this.body,
      required this.createdAt,
      required this.targetType,
      required this.targetId,
      this.targetName = '',
      this.readAt});
  final String id, kind, title, body, targetType, targetId, targetName;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get unread => readAt == null;
  factory AppNotification.fromDocument(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    String text(String key) => d[key] is String ? d[key] as String : '';
    return AppNotification(
        id: doc.id,
        kind: text('kind'),
        title: text('title'),
        body: text('body'),
        targetType: text('targetType'),
        targetId: text('targetId'),
        targetName: text('targetName'),
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        readAt: (d['readAt'] as Timestamp?)?.toDate());
  }
}
