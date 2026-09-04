import 'dart:math';

/// String helpers mirroring Laravel's `Str` facade (Phase 1 subset).
abstract final class Str {
  static final Random _secureRandom = Random.secure();

  /// `PostController` -> `post_controller`.
  static String snake(String value, [String delimiter = '_']) {
    final withDelims = value
        .replaceAll(RegExp(r'[\s\-]+'), delimiter)
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])([A-Z])'),
          (m) => '$delimiter${m[1]}',
        )
        .replaceAllMapped(
          RegExp(r'(?<=[A-Z])([A-Z])'),
          (m) => '$delimiter${m[1]}',
        );
    return withDelims.toLowerCase();
  }

  /// `post_controller` -> `PostController`.
  static String studly(String value) {
    return value
        .split(RegExp(r'[\s_\-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join();
  }

  /// `post_controller` -> `postController`.
  static String camel(String value) {
    final studly = Str.studly(value);
    return studly.isEmpty
        ? studly
        : studly[0].toLowerCase() + studly.substring(1);
  }

  /// `PostController` -> `post-controller`.
  static String kebab(String value) => snake(value, '-');

  /// `OrderShipped` -> `Order Shipped`.
  static String headline(Object value) => snake(value.toString())
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');

  /// Returns a cryptographically random RFC 4122 version 4 UUID.
  static String uuid() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
