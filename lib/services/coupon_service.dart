import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CouponService {
  CouponService(
      {FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  Stream<QuerySnapshot<Map<String, dynamic>>> coupons() {
    final uid = _auth.currentUser?.uid;
    return uid == null
        ? const Stream.empty()
        : _db.collection('users').doc(uid).collection('coupons').snapshots();
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    if (_auth.currentUser == null) throw StateError('로그인이 필요합니다.');
    await (_functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3'))
        .httpsCallable(name)
        .call(data);
  }

  Future<void> claim() => _call('claimMonthlyCoupon', {});
  Future<void> apply(String lessonId, String couponId) =>
      _call('applyLessonCoupon', {'lessonId': lessonId, 'couponId': couponId});
  Future<void> remove(String lessonId) =>
      _call('removeLessonCoupon', {'lessonId': lessonId});
}

String couponError(Object error) {
  if (error is FirebaseFunctionsException) {
    if (error.code == 'unauthenticated') return '다시 로그인해 주세요.';
    if (error.code == 'unavailable') return '연결을 확인한 뒤 다시 시도해 주세요.';
    if (error.message?.isNotEmpty == true) return error.message!;
  }
  return '할인권을 처리하지 못했습니다. 다시 시도해 주세요.';
}
