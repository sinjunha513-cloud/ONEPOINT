bool get supported => false;
bool get granted => false;
Future<bool> requestPermission() async => false;
Future<Map<String, dynamic>> subscribe(String publicKey, String uid) async =>
    throw UnsupportedError('브라우저 알림을 지원하지 않습니다.');
Future<void> clearSession(String uid) async {}
void listen(void Function(Map<String, dynamic>) callback) {}
Map<String, dynamic>? initialNotification() => null;
