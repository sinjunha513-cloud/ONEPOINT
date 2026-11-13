import 'dart:collection';

/// A small in-memory cache for data that is safe to reuse briefly.
///
/// Entries expire after [timeToLive], the oldest entry is evicted when
/// [maxEntries] is reached, and concurrent requests for the same key share one
/// server call. The cache lives only while the app process is running.
class TtlMemoryCache<K, V> {
  TtlMemoryCache({
    required this.timeToLive,
    this.maxEntries = 50,
    DateTime Function()? clock,
  })  : assert(!timeToLive.isNegative),
        assert(maxEntries > 0),
        _clock = clock ?? DateTime.now;

  final Duration timeToLive;
  final int maxEntries;
  final DateTime Function() _clock;
  final LinkedHashMap<K, _CacheEntry<V>> _entries = LinkedHashMap();
  final Map<K, Future<V>> _inFlight = {};

  V? getIfFresh(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_clock().isBefore(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }

    // Move a hit to the end so the least recently used item is evicted first.
    _entries.remove(key);
    _entries[key] = entry;
    return entry.value;
  }

  Future<V> get(K key, Future<V> Function() loadFromServer) {
    final cached = getIfFresh(key);
    if (cached != null) return Future.value(cached);

    final running = _inFlight[key];
    if (running != null) return running;

    final request = loadFromServer().then((value) {
      put(key, value);
      return value;
    }).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = request;
    return request;
  }

  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = _CacheEntry(value, _clock().add(timeToLive));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  int get length => _entries.length;
}

class _CacheEntry<V> {
  const _CacheEntry(this.value, this.expiresAt);

  final V value;
  final DateTime expiresAt;
}
