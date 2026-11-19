import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/services/coach_availability_service.dart';
import 'support/fake_functions.dart';

List<AvailabilityRange> _ranges(int count) => List.generate(count, (index) {
      final start = DateTime.utc(2036, 1, 1).add(Duration(hours: index));
      return (startAt: start, endAt: start.add(const Duration(hours: 1)));
    });

void main() {
  late MockFirebaseAuth auth;
  setUp(() {
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'coach'));
  });
  CoachAvailabilityService service(FunctionHandler handler) =>
      CoachAvailabilityService(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          functions: FakeFunctions(handler));

  test('250 selections use bounded batches and report confirmed progress',
      () async {
    final sizes = <int>[];
    final progress = <int>[];
    final subject = service((name, data) async {
      expect(name, 'saveAvailabilitySlots');
      expect(data['coachUid'], 'coach');
      final slots = data['slots'] as List;
      sizes.add(slots.length);
      return {
        'slotIds': [for (final slot in slots) '${slot['startAtMillis']}']
      };
    });
    final result = await subject.saveSlots(_ranges(250).reversed.toList(),
        onProgress: (done, total) {
      expect(total, 250);
      progress.add(done);
    });
    expect(sizes, [100, 100, 50]);
    expect(progress, [100, 200, 250]);
    expect(result.toSet(), hasLength(250));
    expect(result.first, '${_ranges(1).first.startAt.millisecondsSinceEpoch}');
  });

  test(
      'partial failure retains confirmed IDs and retries only remaining ranges',
      () async {
    final sizes = <int>[];
    final subject = service((_, data) async {
      final slots = data['slots'] as List;
      sizes.add(slots.length);
      if (sizes.length == 2) {
        throw FirebaseFunctionsException(
            code: 'unavailable', message: 'offline');
      }
      return {
        'slotIds': [for (final slot in slots) '${slot['startAtMillis']}']
      };
    });
    AvailabilityBatchException? failure;
    try {
      await subject.saveSlots(_ranges(250));
    } on AvailabilityBatchException catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    expect(failure!.savedSlotIds, hasLength(100));
    expect(failure.remainingRanges, _ranges(250).sublist(100));
    final retried = await subject.saveSlots(failure.remainingRanges);
    expect(sizes, [100, 100, 100, 50]);
    expect({...failure.savedSlotIds, ...retried}, hasLength(250));
  });

  test(
      'account change stops the next batch without submitting for another user',
      () async {
    var calls = 0;
    final subject = service((_, data) async {
      calls++;
      await auth.signOut();
      return {
        'slotIds': List.generate((data['slots'] as List).length, (i) => '$i')
      };
    });
    await expectLater(
        subject.saveSlots(_ranges(250)),
        throwsA(isA<AvailabilityBatchException>()
            .having((e) => e.savedSlotIds.length, 'confirmed', 100)
            .having((e) => e.remainingRanges.length, 'remaining', 150)));
    expect(calls, 1);
  });

  test('overlapping selections fail before any batch is written', () async {
    var calls = 0;
    final subject = service((_, __) async {
      calls++;
      return {};
    });
    final ranges = _ranges(2);
    await expectLater(
        subject.saveSlots([ranges.first, ranges.first, ranges.last]),
        throwsStateError);
    expect(calls, 0);
  });
}
