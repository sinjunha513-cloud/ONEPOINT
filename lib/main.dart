import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 💡 웹/모바일 통합 Firebase 옵션 파일
import 'screens/splash_screen.dart';
import 'utils/page_transitions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'config/payment_environment.dart';
import 'screens/payment_demo_screen.dart';
import 'screens/payment_result_screen.dart';
import 'services/payment_deep_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  if (!paymentDemo &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(NotificationService.initialize().catchError((Object error) {
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
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: OnepointPageTransitionsBuilder(),
          TargetPlatform.iOS: OnepointPageTransitionsBuilder(),
          TargetPlatform.macOS: OnepointPageTransitionsBuilder(),
          TargetPlatform.windows: OnepointPageTransitionsBuilder(),
          TargetPlatform.linux: OnepointPageTransitionsBuilder(),
          TargetPlatform.fuchsia: OnepointPageTransitionsBuilder(),
        }),
        // 1. Pretendard 전역 폰트 적용
        fontFamily: 'Pretendard',

        // 2. 플랫폼 전체 배경색 (Black)
        scaffoldBackgroundColor: const Color(0xFF0D0F12),

        // 3. AppBar 등 공통 컴포넌트 색상 (Indigo Black)
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141620), // 인디고 블랙
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        // 4. 기본 텍스트 색상 (White)
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
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
