import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/config/signature_badge_palette.dart';
import 'package:onepoint_lesson/services/signature_badge_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SignatureBadgeService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('coach').set({
      'role': 'coach',
      'name': '코치',
    });
    await db.collection('instructors').doc('coach').set({
      'uid': 'coach',
      'userId': 'coach',
      'name': '코치',
      'sport': '축구',
      'career': '지도 경력',
      'status': 'approved',
    });
    service = SignatureBadgeService(
      firestore: db,
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'coach'),
        signedIn: true,
      ),
    );
  });

  test('a normalized duplicate returns and reuses the global badge', () async {
    final first = await service.createOrGet('Dribble');
    final duplicate = await service.createOrGet('dribble');

    expect(first.created, true);
    expect(duplicate.created, false);
    expect(duplicate.badge.id, first.badge.id);
    expect(duplicate.badge.name, 'Dribble');
    expect((await db.collection('signature_badges').get()).docs, hasLength(1));
    expect(
        (await db.collection('signature_badge_meta').doc('catalog').get())
            .data()!['nextSequence'],
        1);
  });

  test('the first thirty registrations use thirty distinct shuffled colors',
      () async {
    final colors = <int>[];
    for (var index = 0; index < 30; index++) {
      final result = await service.createOrGet('기술$index');
      colors.add(result.badge.colorIndex);
    }

    expect(colors.toSet(), hasLength(30));
    expect(colors, signatureBadgeColorOrder);
    final next = await service.createOrGet('기술30');
    expect(next.badge.colorIndex, colors.first);
  });

  test('selecting a catalog badge updates coach and instructor together',
      () async {
    final result = await service.createOrGet('드리블');
    await service.selectForCurrentCoach(result.badge);

    for (final collection in ['users', 'instructors']) {
      final data = (await db.collection(collection).doc('coach').get()).data()!;
      expect(data['signatureMove'], '드리블');
      expect(data['signatureBadgeId'], '드리블');
      expect(data['signatureBadgeColorIndex'], result.badge.colorIndex);
    }
  });

  test('spaces and punctuation are rejected before a server write', () async {
    for (final invalid in ['두 단어', '패스!', '', '기' * 21]) {
      await expectLater(service.createOrGet(invalid), throwsArgumentError);
    }
    expect((await db.collection('signature_badges').get()).docs, isEmpty);
  });
}
