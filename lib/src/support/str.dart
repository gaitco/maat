/// String helpers mirroring Laravel's `Str` facade (Phase 1 subset).
abstract final class Str {
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

  /// `PostController` -> `post-controller`.
  static String kebab(String value) => snake(value, '-');

  /// `OrderShipped` -> `Order Shipped`.
  static String headline(Object value) => snake(value.toString())
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
