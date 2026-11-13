import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/feed_service.dart';
import 'support/fake_functions.dart';

void main() {
  test('likes use callable and do not read or mutate private author documents',
      () async {
    final db = FakeFirebaseFirestore();
    final calls = <Map<String, dynamic>>[];
    final service = FeedService(
        firestore: db,
        auth:
            MockFirebaseAuth(mockUser: MockUser(uid: 'viewer'), signedIn: true),
        functions: FakeFunctions((name, data) async {
          expect(name, 'setFeedLiked');
          calls.add(data);
          return {'liked': data['liked']};
        }));
    await service.setLiked('video', liked: true);
    await service.setLiked('video', liked: false);
    expect(calls, [
      {'videoId': 'video', 'liked': true},
      {'videoId': 'video', 'liked': false}
    ]);
    expect((await db.collection('users').get()).docs, isEmpty);
    expect((await db.collection('feed_videos').get()).docs, isEmpty);
  });
  test('server authorization errors propagate without a client write',
      () async {
    final db = FakeFirebaseFirestore();
    final service = FeedService(
        firestore: db,
        auth:
            MockFirebaseAuth(mockUser: MockUser(uid: 'viewer'), signedIn: true),
        functions: FakeFunctions((name, data) async {
          throw FirebaseFunctionsException(
              code: 'permission-denied', message: 'denied');
        }));
    await expectLater(service.setLiked('video', liked: true),
        throwsA(isA<FirebaseFunctionsException>()));
    expect((await db.collection('users').get()).docs, isEmpty);
  });
  test('signed out viewers cannot like and watchLiked is false', () async {
    final service = FeedService(
        firestore: FakeFirebaseFirestore(), auth: MockFirebaseAuth());
    await expectLater(service.setLiked('video', liked: true), throwsStateError);
    expect(await service.watchLiked('video').first, isFalse);
  });
  test('watchLiked observes only the signed in viewer record', () async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('feed_videos')
        .doc('video')
        .collection('likes')
        .doc('viewer')
        .set({'userId': 'viewer'});
    final service = FeedService(
        firestore: db,
        auth: MockFirebaseAuth(
            mockUser: MockUser(uid: 'viewer'), signedIn: true));
    expect(await service.watchLiked('video').first, isTrue);
  });
}
