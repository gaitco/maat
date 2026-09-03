/// Dot-notation configuration repository (`config('app.name')`).
class Config {
  Config(Map<String, dynamic> items) : _items = _deepCopy(items);

  /// The active config. Set by `Application` and by tests.
  static Config current = Config({});

  final Map<String, dynamic> _items;

  Map<String, dynamic> all() => _items;

  dynamic get(String key, [Object? defaultValue]) {
    dynamic node = _items;
    for (final segment in key.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else {
        return defaultValue;
      }
    }
    return node;
  }

  bool has(String key) {
    dynamic node = _items;
    for (final segment in key.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else {
        return false;
      }
    }
    return true;
  }

  void set(String key, Object? value) {
    final segments = key.split('.');
    Map<String, dynamic> node = _items;
    for (final segment in segments.take(segments.length - 1)) {
      final next = node[segment];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[segment] = created;
        node = created;
      }
    }
    node[segments.last] = value;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) => {
    for (final e in source.entries)
      e.key: e.value is Map<String, dynamic>
          ? _deepCopy(e.value as Map<String, dynamic>)
          : e.value,
  };
}

dynamic config(String key, [Object? defaultValue]) =>
    Config.current.get(key, defaultValue);
