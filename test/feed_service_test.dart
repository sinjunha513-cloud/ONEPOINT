import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/feed_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FeedService service;

  FeedService serviceFor(String uid) => FeedService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: uid),
          signedIn: true,
        ),
      );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('author').set({
      'feedLikeCount': 2,
      'name': '코치',
    });
    await firestore.collection('feed_videos').doc('video').set({
      'userId': 'author',
      'likes': 0,
    });
    service = serviceFor('viewer');
  });

  test('repeated like adds one viewer record and one author EXP counter',
      () async {
    await service.setLiked('video', liked: true);
    await service.setLiked('video', liked: true);

    final video = await firestore.collection('feed_videos').doc('video').get();
    final author = await firestore.collection('users').doc('author').get();
    final likes = await video.reference.collection('likes').get();
    expect(video.data()!['likes'], 1);
    expect(author.data()!['feedLikeCount'], 3);
    expect(author.data()!['name'], '코치');
    expect(likes.docs.map((doc) => doc.id), ['viewer']);
    expect(likes.docs.single.data()['userId'], 'viewer');
    expect(await service.watchLiked('video').first, isTrue);
  });

  test('unlike is idempotent and keeps the other viewer like', () async {
    final secondViewer = serviceFor('other-viewer');
    await service.setLiked('video', liked: true);
    await secondViewer.setLiked('video', liked: true);
    await service.setLiked('video', liked: false);
    await service.setLiked('video', liked: false);

    final video = await firestore.collection('feed_videos').doc('video').get();
    final author = await firestore.collection('users').doc('author').get();
    final likes = await video.reference.collection('likes').get();
    expect(video.data()!['likes'], 1);
    expect(author.data()!['feedLikeCount'], 3);
    expect(likes.docs.map((doc) => doc.id), ['other-viewer']);
    expect(await service.watchLiked('video').first, isFalse);
  });

  test('unlike never makes legacy missing counters negative', () async {
    final videoRef = firestore.collection('feed_videos').doc('video');
    await videoRef.set({'userId': 'author'});
    await firestore.collection('users').doc('author').set({'name': '코치'});
    await videoRef.collection('likes').doc('viewer').set({'userId': 'viewer'});

    await service.setLiked('video', liked: false);

    expect((await videoRef.get()).data()!['likes'], 0);
    expect(
      (await firestore.collection('users').doc('author').get())
          .data()!['feedLikeCount'],
      0,
    );
  });

  test('own video cannot increase counters', () async {
    final authorService = serviceFor('author');
    await expectLater(
      authorService.setLiked('video', liked: true),
      throwsStateError,
    );
    expect(
      (await firestore.collection('feed_videos').doc('video').get())
          .data()!['likes'],
      0,
    );
    expect(
      (await firestore.collection('users').doc('author').get())
          .data()!['feedLikeCount'],
      2,
    );
  });

  test('signed out viewers cannot like', () async {
    final signedOut = FeedService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
    );
    await expectLater(
      signedOut.setLiked('video', liked: true),
      throwsStateError,
    );
    expect(await signedOut.watchLiked('video').first, isFalse);
  });

  test('deleted author prevents partial video and like writes', () async {
    await firestore.collection('users').doc('author').delete();
    await expectLater(
      service.setLiked('video', liked: true),
      throwsStateError,
    );
    final video = await firestore.collection('feed_videos').doc('video').get();
    expect(video.data()!['likes'], 0);
    expect((await video.reference.collection('likes').get()).docs, isEmpty);
  });

  test('deleted video cannot be liked or recreated', () async {
    final videoRef = firestore.collection('feed_videos').doc('video');
    await videoRef.delete();
    await expectLater(
      service.setLiked('video', liked: true),
      throwsStateError,
    );
    expect((await videoRef.get()).exists, isFalse);
    expect((await videoRef.collection('likes').get()).docs, isEmpty);
  });
}
