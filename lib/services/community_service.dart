import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommunityService {
  CommunityService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseFunctions? functions})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        _functions = functions;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseFunctions? _functions;
  String get uid => auth.currentUser?.uid ?? (throw StateError('로그인이 필요합니다.'));
  FirebaseFunctions get _api =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  Stream<QuerySnapshot<Map<String, dynamic>>> blocked() => firestore
      .collection('user_blocks')
      .doc(uid)
      .collection('members')
      .snapshots();
  Future<bool> isBlocked(String other) async =>
      (await firestore.doc('user_blocks/$uid/members/$other').get()).exists;
  Future<void> setBlocked(String other, bool blocked) async {
    await _api
        .httpsCallable('setUserBlocked')
        .call({'targetUid': other, 'blocked': blocked});
  }

  Future<void> report(
      {required String targetType,
      required String targetId,
      required String reason,
      required String details,
      required String requestId}) async {
    await _api.httpsCallable('submitReport').call({
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'details': details,
      'requestId': requestId
    });
  }

  String newRequestId() => firestore.collection('reports').doc().id;
  Future<void> resolveReport(String id, String decision, String reason) async {
    await _api
        .httpsCallable('resolveReport')
        .call({'reportId': id, 'decision': decision, 'reason': reason});
  }
}

String communityError(Object e) {
  if (e is FirebaseFunctionsException && e.code != 'internal') {
    return e.message ?? '요청을 처리하지 못했습니다.';
  }
  if (e is StateError) return e.message.toString();
  return '요청을 처리하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
}
