import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'push_browser_stub.dart' if (dart.library.html) 'push_browser_web.dart'
    as browser;
import '../screens/notifications_screen.dart';

class NotificationService {
  static bool _initialized = false;
  static String? _deviceId, _deviceOwner, _readyUid;
  static GlobalKey<NavigatorState>? _navigator;
  static Map<String, dynamic>? _pending;
  static Future<void> _sessionWork = Future<void>.value();
  static Future<void> _queue(Future<void> Function() task) {
    final next = _sessionWork.then((_) => task());
    _sessionWork = next.catchError((Object _) {});
    return next;
  }

  static final _local = FlutterLocalNotificationsPlugin();
  static FirebaseFunctions get _api =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static bool get supported => kIsWeb
      ? browser.supported
      : [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform);
  static Future<Map<String, dynamic>> configuration() async =>
      Map<String, dynamic>.from((await _api
              .httpsCallable('getPushConfiguration')
              .call(<String, dynamic>{}))
          .data as Map);

  static Future<void> initialize(
      {GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialized || !supported) return;
    _initialized = true;
    _navigator = navigatorKey;
    if (kIsWeb) {
      browser.listen(_tap);
      _pending = browser.initialNotification();
    } else {
      await _local.initialize(
          const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(
                  requestAlertPermission: false,
                  requestBadgePermission: false,
                  requestSoundPermission: false)),
          onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            _tap(Map<String, dynamic>.from(
                jsonDecode(response.payload!) as Map));
          } catch (_) {}
        }
      });
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['ownerUid'] != _uid) return;
        _local.show(
            m.messageId.hashCode,
            m.notification?.title ?? 'onepoint',
            m.notification?.body ?? '',
            const NotificationDetails(
                android: AndroidNotificationDetails(
                    'onepoint_channel', 'onepoint 알림',
                    importance: Importance.high, priority: Priority.high),
                iOS: DarwinNotificationDetails()),
            payload: jsonEncode(m.data));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _tap(m.data));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pending = initial.data;
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_deviceOwner == _uid && _uid != null) {
          _register(_uid!, {'provider': 'fcm', 'token': token})
              .catchError((Object _) {});
        }
      });
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_readyUid != user?.uid) _readyUid = null;
      unawaited(_queue(() async {
        if (_uid != user?.uid) return;
        final old = _deviceOwner;
        if (old == null || old != user?.uid) {
          try {
            // A page/app restart may retain an old push subscription while
            // local Auth is already signed out or belongs to another account.
            await _detach(old ?? '', clearUnknownSession: old == null);
          } catch (_) {}
        }
        if (user != null) {
          try {
            final c = await configuration();
            if (_uid == user.uid && c['enabled'] == true) {
              await _connect(user.uid, c, ask: false);
            }
          } catch (_) {}
        }
      }));
    });
  }

  static Future<void> enable() async {
    if (!supported) {
      throw StateError('이 브라우저에서는 기기 알림을 지원하지 않습니다. 앱 안의 알림함을 이용해 주세요.');
    }
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final granted = kIsWeb
        ? await browser.requestPermission()
        : (await FirebaseMessaging.instance.requestPermission())
                .authorizationStatus ==
            AuthorizationStatus.authorized;
    if (!granted) {
      throw StateError('알림이 허용되지 않았습니다. 기기 또는 브라우저 설정에서 알림을 허용해 주세요.');
    }
    await _queue(() async {
      if (_uid != uid) return;
      await _connect(uid, await configuration(), ask: true);
    });
  }

  static Future<void> _connect(String uid, Map<String, dynamic> config,
      {required bool ask}) async {
    if (_uid != uid) return;
    // Track the owner before asynchronous subscription/registration starts.
    // A subsequent auth event must clear this session even if it changed while
    // the server registration response was still in flight.
    _deviceOwner = uid;
    if (kIsWeb) {
      if (!browser.granted) return;
      if (config['publicKey'] is! String) {
        throw StateError('알림 설정을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
      final sub = await browser.subscribe(config['publicKey'] as String, uid);
      if (_uid == uid) {
        await _register(uid, {'provider': 'web', 'subscription': sub});
      }
    } else {
      if (!ask &&
          (await FirebaseMessaging.instance.getNotificationSettings())
                  .authorizationStatus !=
              AuthorizationStatus.authorized) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) throw StateError('기기 알림 연결을 완료하지 못했습니다.');
      if (_uid == uid) {
        await _register(uid, {'provider': 'fcm', 'token': token});
      }
    }
  }

  static Future<void> _register(
      String uid, Map<String, dynamic> payload) async {
    if (_uid != uid) return;
    final result = await _api.httpsCallable('registerPushDevice').call(payload);
    if (_uid == uid) {
      _deviceId = (result.data as Map)['deviceId'] as String;
      _deviceOwner = uid;
    }
  }

  static Future<void> setPreviews(bool value) async {
    await _api.httpsCallable('setPushPreference').call({'previews': value});
  }

  static Future<void> disable() async {
    final uid = _uid;
    if (uid == null) return;
    await _api.httpsCallable('setPushPreference').call({'enabled': false});
    await detach(uid);
  }

  static Future<void> detach(String uid) async {
    if (!_initialized) return;
    await _queue(() => _detach(uid));
  }

  static Future<void> _detach(String uid,
      {bool clearUnknownSession = false}) async {
    final id = _deviceOwner == uid ? _deviceId : null;
    try {
      if (kIsWeb) {
        await browser.clearSession(clearUnknownSession ? '' : uid);
      } else if (clearUnknownSession || _deviceOwner == uid || _uid == uid) {
        await FirebaseMessaging.instance.deleteToken();
        await _local.cancelAll();
      }
    } finally {
      if (id != null && _uid == uid) {
        try {
          await _api
              .httpsCallable('unregisterPushDevice')
              .call({'deviceId': id});
        } catch (_) {}
      }
      if (_deviceOwner == uid) {
        _deviceOwner = null;
        _deviceId = null;
      }
    }
  }

  static void _tap(Map<String, dynamic> data) {
    _pending = data;
    _openPending();
  }

  static void sessionReady(String uid) {
    if (!_initialized) return;
    _readyUid = uid;
    _openPending();
  }

  static void _openPending() {
    final p = _pending, navigator = _navigator?.currentState;
    if (p == null ||
        navigator == null ||
        _uid != p['ownerUid'] ||
        _readyUid != _uid) {
      return;
    }
    final id = p['notificationId'];
    _pending = null;
    if (id is String && RegExp(r'^[-_a-zA-Z0-9]{1,128}$').hasMatch(id)) {
      navigator.push(MaterialPageRoute(
          builder: (_) => NotificationsScreen(initialNotificationId: id)));
    }
  }
}
