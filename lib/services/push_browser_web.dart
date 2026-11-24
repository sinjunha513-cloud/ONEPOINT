import 'dart:js_interop';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:web/web.dart' as web;

@JS('Notification')
external JSObject? get _notification;
@JS('PushManager')
external JSObject? get _pushManager;

bool get supported {
  try {
    final controller = web.window.navigator.serviceWorker.controller;
    return web.window.isSecureContext &&
        _notification != null &&
        _pushManager != null &&
        (controller == null || controller.scriptURL.isNotEmpty);
  } catch (_) {
    return false;
  }
}

bool get granted => supported && web.Notification.permission == 'granted';
Future<bool> requestPermission() async =>
    supported &&
    (await web.Notification.requestPermission().toDart).toDart == 'granted';
web.ServiceWorkerRegistration? _registration;
Future<web.ServiceWorkerRegistration> _worker() async =>
    _registration ??= await web.window.navigator.serviceWorker
        .register('/onepoint-push-sw.js',
            web.RegistrationOptions(scope: '/onepoint-push/'))
        .toDart;
Future<bool> _bind(web.ServiceWorkerRegistration registration, String? uid,
    String? previous) async {
  var worker = registration.active;
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (worker == null && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    worker = registration.active;
  }
  if (worker == null) throw StateError('알림 연결이 준비되지 않았습니다. 다시 시도해 주세요.');
  final channel = web.MessageChannel(), done = Completer<bool>();
  final handler = ((web.Event event) {
    final data = (event as web.MessageEvent).data.dartify();
    if (data is Map && data['ok'] == true) {
      if (!done.isCompleted) done.complete(data['cleared'] == true);
    } else if (!done.isCompleted) {
      done.completeError(StateError('이 브라우저에서는 기기 알림을 사용할 수 없습니다.'));
    }
  }).toJS;
  channel.port1.addEventListener('message', handler);
  channel.port1.start();
  try {
    worker.postMessage(
        {'type': 'ONEPOINT_SESSION', 'uid': uid, 'expectedUid': previous}
            .jsify(),
        [channel.port2].toJS);
    return await done.future.timeout(const Duration(seconds: 8));
  } finally {
    channel.port1.removeEventListener('message', handler);
    channel.port1.close();
    channel.port2.close();
  }
}

Future<Map<String, dynamic>> subscribe(String publicKey, String uid) async {
  if (!granted) throw StateError('브라우저 설정에서 알림을 허용해 주세요.');
  final registration = await _worker();
  var subscription = await registration.pushManager.getSubscription().toDart;
  subscription ??= await registration.pushManager
      .subscribe(web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: Uint8List.fromList(
                  base64Url.decode(base64Url.normalize(publicKey)))
              .toJS))
      .toDart;
  await _bind(registration, uid, null);
  return Map<String, dynamic>.from(subscription.toJSON().dartify() as Map);
}

Future<void> clearSession(String uid) async {
  if (!supported) return;
  final registration = await web.window.navigator.serviceWorker
      .getRegistration('/onepoint-push/')
      .toDart;
  if (registration == null) return;
  if (!await _bind(registration, null, uid)) return;
  final subscription = await registration.pushManager.getSubscription().toDart;
  if (subscription != null) await subscription.unsubscribe().toDart;
}

void listen(void Function(Map<String, dynamic>) callback) {
  if (!supported) return;
  web.window.navigator.serviceWorker.addEventListener(
      'message',
      ((web.Event event) {
        final data = (event as web.MessageEvent).data.dartify();
        if (data is Map && data['type'] == 'ONEPOINT_OPEN_NOTIFICATION') {
          callback(Map<String, dynamic>.from(data));
        }
      }).toJS);
}

Map<String, dynamic>? initialNotification() {
  final q = Uri.base.queryParameters;
  return q['notificationId'] == null
      ? null
      : {'notificationId': q['notificationId'], 'ownerUid': q['ownerUid']};
}
