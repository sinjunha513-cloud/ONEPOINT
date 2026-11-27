import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/screens/shortform_feed_screen.dart';
import 'package:onepoint_lesson/services/feed_service.dart';
import 'package:onepoint_lesson/widget/video_item_widget.dart';

void main() {
  testWidgets(
      'automatic feed pagination keeps the currently visible video while adding the next page',
      (tester) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 22; i++) {
      await db.doc('public_feed_videos/clip-$i').set({
        'userId': 'author',
        'userName': '작성자',
        'title': '영상 $i',
        'description': '',
        'videoUrl': '',
        'likes': 0,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(22000 - i * 1000)
      });
    }
    final service = FeedService(
        firestore: db,
        auth: MockFirebaseAuth(
            mockUser: MockUser(uid: 'viewer'), signedIn: true));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: ShortformFeedScreen(
            isActive: false, firestore: db, feedService: service)));
    await tester.pumpAndSettle();
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(18);
    await tester.pumpAndSettle();
    expect(find.text('19 / 22'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('shortform-card-clip-18')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    '숏폼은 작은 9:16 카드로 표시되고 위아래로 넘길 수 있다',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('public_feed_videos').doc('mine').set({
        'userId': 'owner',
        'userName': '내 계정',
        'title': '첫 영상',
        'description': '화면을 채우지 않는 카드',
        'videoUrl': 'https://example.test/mine.mp4',
        'storagePath': 'videos/owner/mine.mp4',
        'likes': 0,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 11, 2)),
      });
      await firestore.collection('public_feed_videos').doc('other').set({
        'userId': 'other',
        'userName': '다른 사용자',
        'title': '두 번째 영상',
        'description': '',
        'videoUrl': 'https://example.test/other.mp4',
        'storagePath': 'videos/other/other.mp4',
        'likes': 3,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 11, 1)),
      });
      final feedService = FeedService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'owner'),
          signedIn: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ShortformFeedScreen(
            isActive: false,
            firestore: firestore,
            feedService: feedService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.scrollDirection, Axis.vertical);
      expect(pageView.pageSnapping, isTrue);
      expect(find.text('영상 추가'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-feed-mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-feed-other')), findsNothing);

      final player = tester.widget<VideoItemWidget>(
        find.byType(VideoItemWidget).first,
      );
      expect(player.fit, BoxFit.contain);

      final cardSize = tester.getSize(
        find.byKey(const ValueKey('shortform-card-mine')),
      );
      expect(cardSize.height, lessThan(380));
      expect(cardSize.width / cardSize.height, closeTo(9 / 16, .01));

      await tester.drag(find.byType(PageView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 500));

      final otherPlayer = tester.widget<VideoItemWidget>(
        find.byKey(const ValueKey('other')),
      );
      expect(otherPlayer.fit, BoxFit.contain);
    },
  );
  testWidgets(
      'feed uses cursor pages, filters blocked authors and fits small screens with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 21; i++) {
      await db.collection('public_feed_videos').doc('video-$i').set({
        'userId': i == 0 ? 'blocked' : 'other',
        'userName': '코치',
        'title': '레슨 영상',
        'description': '완료한 수업 영상을 확인하세요.',
        'videoUrl': '',
        'likes': 0,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(21000 - i * 1000),
      });
    }
    await db.doc('user_blocks/owner/members/blocked').set({'name': '차단된 회원'});
    final service = FeedService(
        firestore: db,
        auth:
            MockFirebaseAuth(mockUser: MockUser(uid: 'owner'), signedIn: true));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!),
      home: ShortformFeedScreen(
          isActive: false, firestore: db, feedService: service),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shortform-card-video-0')), findsNothing);
    expect(find.text('1 / 19'), findsOneWidget);
    expect(find.text('영상 더 보기'), findsOneWidget);
    await tester.tap(find.text('영상 더 보기'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 20'), findsOneWidget);
    expect(find.text('영상 더 보기'), findsNothing);
  });
}
