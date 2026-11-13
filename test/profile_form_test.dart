import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/signup_screen.dart';

Finder field(String name) => find.byKey(ValueKey('profile-$name'));

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  const photo =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==';

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(
          uid: 'member', email: 'member@example.com', displayName: '구글 이름'),
      signedIn: true,
    );
  });

  Future<void> largeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('registration and editing expose the same full profile fields',
      (tester) async {
    await largeScreen(tester);
    for (final editing in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: SignupScreen(
        key: ValueKey(editing),
        role: 'student',
        isEditing: editing,
        initialData: editing
            ? {
                'name': '기존 이름',
                'email': 'member@example.com',
                'targetTier': '프로 2',
                'aspirations': '기존 소개',
                'videoUrl': 'https://example.com/video'
              }
            : null,
        auth: auth,
        firestore: db,
      )));
      await tester.pumpAndSettle();
      for (final name in [
        'email',
        'name',
        'image',
        'tier',
        'aspirations',
        'video',
        'save'
      ]) {
        expect(field(name), findsOneWidget);
      }
      expect(field('password'), editing ? findsNothing : findsOneWidget);
      expect(tester.widget<TextField>(field('email')).readOnly, editing);
      if (editing) {
        expect(
            tester.widget<TextField>(field('name')).controller!.text, '기존 이름');
        expect(
            tester.widget<DropdownButton<String>>(field('tier')).value, '프로 2');
        expect(tester.widget<TextField>(field('video')).controller!.text,
            'https://example.com/video');
      }
    }
  });

  testWidgets(
      'saving edit retains uploaded photo and progress while saving video and all fields',
      (tester) async {
    await largeScreen(tester);
    final initial = <String, dynamic>{
      'email': 'member@example.com',
      'name': '이전 이름',
      'profileImage': photo,
      'targetTier': '프로 2',
      'aspirations': '이전 소개',
      'videoUrl': 'https://example.com/old',
      'role': 'coach',
      'lessonCount': 9,
    };
    await db.collection('users').doc('member').set(initial);
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        saved = await Navigator.of(context)
                            .push<bool>(MaterialPageRoute(
                                builder: (_) => SignupScreen(
                                      role: 'coach',
                                      isEditing: true,
                                      initialData: initial,
                                      auth: auth,
                                      firestore: db,
                                    )));
                      },
                      child: const Text('프로필 수정')),
                ))));
    await tester.tap(find.text('프로필 수정'));
    await tester.pumpAndSettle();
    // The uploaded image stays in the preview without filling the URL field with base64.
    expect(tester.widget<TextField>(field('image')).controller!.text, '');
    await tester.enterText(field('name'), '수정한 이름');
    await tester.enterText(field('aspirations'), '수정한 소개');
    await tester.enterText(field('video'), 'https://example.com/new');
    await tester.ensureVisible(field('save'));
    await tester.tap(field('save'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    final data = (await db.collection('users').doc('member').get()).data()!;
    expect(data['name'], '수정한 이름');
    expect(data['aspirations'], '수정한 소개');
    expect(data['videoUrl'], 'https://example.com/new');
    expect(data['profileImage'], photo);
    expect(data['targetTier'], '프로 2');
    expect(data['lessonCount'], 9);
    expect(data['role'], 'coach');
  });

  testWidgets('Google onboarding loads saved partial profile without password',
      (tester) async {
    await largeScreen(tester);
    await db.collection('users').doc('member').set({
      'name': '이전에 저장한 이름',
      'photoUrl': photo,
      'bio': '기존 자기소개',
      'targetTier': '세미프로 1',
      'videoUrl': 'https://example.com/practice',
      'profileCompleted': false,
    });
    await tester.pumpWidget(MaterialApp(
        home: SignupScreen(
      role: 'student',
      completeProfile: true,
      auth: auth,
      firestore: db,
    )));
    await tester.pumpAndSettle();
    expect(find.text('수강생 프로필 등록'), findsOneWidget);
    expect(field('password'), findsNothing);
    expect(tester.widget<TextField>(field('email')).readOnly, isTrue);
    expect(tester.widget<TextField>(field('email')).controller!.text,
        'member@example.com');
    expect(
        tester.widget<TextField>(field('name')).controller!.text, '이전에 저장한 이름');
    expect(tester.widget<TextField>(field('aspirations')).controller!.text,
        '기존 자기소개');
    expect(tester.widget<TextField>(field('video')).controller!.text,
        'https://example.com/practice');
    expect(
        tester.widget<DropdownButton<String>>(field('tier')).value, '세미프로 1');
  });

  testWidgets('new Google account starts with Google name and email',
      (tester) async {
    await largeScreen(tester);
    await tester.pumpWidget(MaterialApp(
        home: SignupScreen(
      role: 'student',
      completeProfile: true,
      auth: auth,
      firestore: db,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('name')).controller!.text, '구글 이름');
    expect(tester.widget<TextField>(field('email')).controller!.text,
        'member@example.com');
    expect(field('password'), findsNothing);
  });

  for (final editing in [true, false]) {
    testWidgets(
        '${editing ? 'editing' : 'onboarding'} rejects a save after another tab changes accounts',
        (tester) async {
      await largeScreen(tester);
      const initial = {
        'name': '원래 사용자',
        'email': 'member@example.com',
        'profileCompleted': false,
        'lessonCount': 3,
      };
      const otherInitial = {
        'name': '다른 사용자',
        'email': 'other@example.com',
        'profileCompleted': false,
        'lessonCount': 7,
      };
      await db.collection('users').doc('member').set(initial);
      await db.collection('users').doc('other').set(otherInitial);
      await tester.pumpWidget(MaterialApp(
          home: SignupScreen(
        role: 'student',
        isEditing: editing,
        completeProfile: !editing,
        initialData: editing ? initial : null,
        auth: auth,
        firestore: db,
      )));
      await tester.pumpAndSettle();
      await tester.enterText(field('name'), '이전 계정의 편집 내용');
      if (!editing) {
        for (final key in ['terms-consent', 'privacy-consent']) {
          final checkbox = find.byKey(ValueKey(key));
          await tester.ensureVisible(checkbox);
          await tester.tap(checkbox);
          await tester.pump();
        }
      }

      auth.mockUser = MockUser(uid: 'other', email: 'other@example.com');
      await tester.ensureVisible(field('save'));
      await tester.tap(field('save'));
      await tester.pumpAndSettle();

      expect(find.text('로그인 계정이 변경되었습니다. 프로필 화면을 다시 열어 주세요.'), findsOneWidget);
      expect(
          (await db.collection('users').doc('member').get()).data(), initial);
      expect((await db.collection('users').doc('other').get()).data(),
          otherInitial);
      expect(find.byType(SignupScreen), findsOneWidget);
    });
  }
}
