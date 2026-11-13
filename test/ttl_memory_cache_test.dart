import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onepoint_lesson/utils/ttl_memory_cache.dart';

void main() {
  test('returns cached data until the TTL expires', () async {
    var now = DateTime(2026, 10, 15);
    var serverCalls = 0;
    final cache = TtlMemoryCache<String, String>(
      timeToLive: const Duration(minutes: 2),
      clock: () => now,
    );

    Future<String> load() async => 'value-${++serverCalls}';

    expect(await cache.get('coach-list', load), 'value-1');
    expect(await cache.get('coach-list', load), 'value-1');
    expect(serverCalls, 1);

    now = now.add(const Duration(minutes: 2));
    expect(await cache.get('coach-list', load), 'value-2');
    expect(serverCalls, 2);
  });

  test('shares concurrent requests and evicts the least recently used item',
      () async {
    final completer = Completer<String>();
    var serverCalls = 0;
    final cache = TtlMemoryCache<String, String>(
      timeToLive: const Duration(minutes: 2),
      maxEntries: 2,
    );

    Future<String> load() {
      serverCalls++;
      return completer.future;
    }

    final first = cache.get('same', load);
    final second = cache.get('same', load);
    expect(serverCalls, 1);
    completer.complete('result');
    expect(await Future.wait([first, second]), ['result', 'result']);

    cache.put('second', '2');
    cache.getIfFresh('same');
    cache.put('third', '3');
    expect(cache.getIfFresh('second'), isNull);
    expect(cache.getIfFresh('same'), 'result');
    expect(cache.length, 2);
  });
}
