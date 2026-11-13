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
    '숏폼은 작은 9:16 카드로 표시되고 위아래로 넘길 수 있다',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('feed_videos').doc('mine').set({
        'userId': 'owner',
        'userName': '내 계정',
        'title': '첫 영상',
        'description': '화면을 채우지 않는 카드',
        'videoUrl': 'https://example.test/mine.mp4',
        'storagePath': 'videos/owner/mine.mp4',
        'likes': 0,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 11, 2)),
      });
      await firestore.collection('feed_videos').doc('other').set({
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
      await tester.pump();

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
}
