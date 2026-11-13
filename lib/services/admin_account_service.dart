import 'package:cloud_functions/cloud_functions.dart';

class AdminAccountService {
  Future<void> manage(String uid, String action, String reason) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('adminManageAccount')
          .call({'uid': uid, 'action': action, 'reason': reason});
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        throw StateError('관리자 계정 관리 서버가 아직 배포되지 않았습니다. Firebase 설정을 완료해 주세요.');
      }
      rethrow;
    }
  }
}
