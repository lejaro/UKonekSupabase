/// Centralized in-memory TTL caching for U-Konek+ Mobile API services.
library;

class CacheEntry {
  final dynamic value;
  final DateTime expiresAt;

  const CacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ApiCache {
  ApiCache._();

  static final Map<String, CacheEntry> _cache = {};

  /// Retrieve a cached value if it exists and hasn't expired.
  static T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  /// Store a value in the cache with a TTL duration.
  static void set<T>(String key, T value, Duration ttl) {
    _cache[key] = CacheEntry(value: value, expiresAt: DateTime.now().add(ttl));
  }

  /// Remove a specific cache entry.
  static void remove(String key) {
    _cache.remove(key);
  }

  /// Remove all cache entries matching a predicate.
  static void removeWhere(bool Function(String key) predicate) {
    _cache.removeWhere((key, _) => predicate(key));
  }

  /// Clear all cached data.
  static void clear() {
    _cache.clear();
  }
}
