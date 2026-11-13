import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/role_selection_screen.dart';
import 'package:onepoint_lesson/screens/signup_screen.dart';

void main() {
  for (final role in ['student', 'coach']) {
    testWidgets('$role selection opens the matching signup form',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));

      await tester.tap(find.text(
        role == 'student' ? '수강생으로 가입하기' : '전문 코치로 가입하기',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(tester.widget<SignupScreen>(find.byType(SignupScreen)).role, role);
      expect(
        find.text(role == 'student' ? '수강생 회원가입' : '전문 코치 회원가입'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('가입 유형 선택'), findsOneWidget);
      expect(find.byType(SignupScreen), findsNothing);
    });
  }
}
