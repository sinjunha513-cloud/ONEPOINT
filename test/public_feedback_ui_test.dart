import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/lesson_feedback_videos_screen.dart';
import 'package:onepoint_lesson/screens/video_upload_screen.dart';
import 'package:onepoint_lesson/services/video_upload_service.dart';

class _Videos implements VideoUploadService {
  _Videos(this.db);
  final FakeFirebaseFirestore db;
  final calls = <bool>[];
  @override
  Future<void> setFeedbackPublic(
      {required String lessonId,
      required String videoId,
      required bool isPublic}) async {
    calls.add(isPublic);
    await db
        .doc('lesson_requests/$lessonId/feedback_videos/$videoId')
        .update({'visibility': isPublic ? 'public' : 'private'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'feedback uploader clearly describes the public audience and upload action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: VideoUploadScreen(
            lessonId: 'lesson', service: _Videos(FakeFirebaseFirestore()))));
    await tester.pumpAndSettle();
    expect(find.textContaining('로그인한 모든 이용자가 영상과 설명'), findsOneWidget);
    expect(find.text('전체 공개로 업로드'), findsOneWidget);
    expect(find.text('피드백 제목 (선택)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'only the uploader can publish an older private clip and then archive it',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final service = _Videos(db);
    await db.doc('lesson_requests/lesson/feedback_videos/clip').set({
      'uploaderUid': 'owner',
      'uploaderName': '작성자',
      'description': '연습 영상',
      'storagePath': 'lesson_feedback/lesson/owner/clip.mp4',
      'createdAt': Timestamp.now()
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: LessonFeedbackVideosScreen(
            lessonId: 'lesson',
            firestore: db,
            auth: MockFirebaseAuth(
                mockUser: MockUser(uid: 'owner'), signedIn: true),
            videoService: service)));
    await tester.pumpAndSettle();
    expect(find.text('레슨 참여자만'), findsOneWidget);
    await tester.tap(find.text('공개 피드에 게시'));
    await tester.pumpAndSettle();
    expect(find.textContaining('로그인한 모든 이용자가 공개 피드'), findsOneWidget);
    await tester.tap(find.text('전체 공개로 게시'));
    await tester.pumpAndSettle();
    expect(service.calls, [true]);
    expect(find.text('전체 공개'), findsOneWidget);
    await tester.tap(find.text('공개 중지'));
    await tester.pumpAndSettle();
    expect(service.calls, [true, false]);
    expect(find.text('레슨 참여자만'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'lesson partners can view feedback but do not get another uploaders publish controls',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('lesson_requests/lesson/feedback_videos/clip').set({
      'uploaderUid': 'owner',
      'uploaderName': '작성자',
      'description': '영상 설명',
      'createdAt': Timestamp.now(),
      'visibility': 'public'
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: LessonFeedbackVideosScreen(
            lessonId: 'lesson',
            firestore: db,
            auth: MockFirebaseAuth(
                mockUser: MockUser(uid: 'partner'), signedIn: true),
            videoService: _Videos(db))));
    await tester.pumpAndSettle();
    expect(find.text('전체 공개'), findsOneWidget);
    expect(find.text('공개 중지'), findsNothing);
    expect(find.text('공개 피드에 게시'), findsNothing);
    expect(find.byTooltip('내 피드백 영상 삭제'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
