import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 💡 웹/모바일 통합 Firebase 옵션 파일
import 'screens/splash_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'config/payment_environment.dart';
import 'screens/payment_demo_screen.dart';
import 'screens/payment_result_screen.dart';
import 'services/payment_deep_links.dart';
import 'config/onepoint_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Inter', 'Pretendard']) {
      final license =
          await rootBundle.loadString('assets/fonts/$family-OFL.txt');
      yield LicenseEntryWithLineBreaks([family], license);
    }
  });

  // 💡 웹 브라우저 및 에뮬레이터 환경 통합 초기화
  await Firebase.initializeApp(
    options: paymentDemo
        ? const FirebaseOptions(
            apiKey: 'demo-only-key',
            appId: '1:123456789:web:demo',
            messagingSenderId: '123456789',
            projectId: 'demo-onepoint-payments',
            authDomain: 'demo-onepoint-payments.firebaseapp.com',
            storageBucket: 'demo-onepoint-payments.appspot.com')
        : DefaultFirebaseOptions.currentPlatform,
  );
  if (paymentDemo) {
    await FirebaseAuth.instance.useAuthEmulator(paymentEmulatorHost, 9198);
    FirebaseFirestore.instance.useFirestoreEmulator(paymentEmulatorHost, 8280);
    await FirebaseStorage.instance
        .useStorageEmulator(paymentEmulatorHost, 9298);
    FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .useFunctionsEmulator(paymentEmulatorHost, 5101);
  }

  runApp(const MyApp());
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(watchPaymentLinks().catchError((Object _) {}));
  }
  if (!paymentDemo) {
    unawaited(NotificationService.initialize(navigatorKey: paymentNavigatorKey)
        .catchError((Object error) {
      debugPrint('알림 초기화 실패: $error');
    }));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: paymentNavigatorKey,
      title: 'ONEPOINT',
      debugShowCheckedModeBanner: false,
      theme: buildOnepointTheme(),
      onGenerateRoute: (settings) {
        final route = Uri.tryParse(settings.name ?? '');
        if (route?.path == '/payment-result') {
          return MaterialPageRoute(
              builder: (_) =>
                  PaymentResultScreen(parameters: route!.queryParameters));
        }
        return null;
      },
      home: paymentDemo ? const PaymentDemoScreen() : const SplashScreen(),
    );
  }
}
