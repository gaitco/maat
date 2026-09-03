import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../foundation/application.dart';

/// Absolute path inside the application's `public/` directory — where
/// compiled assets land, and what `PublicFiles` serves.
///
/// ```dart
/// publicPath()               // /app/public
/// publicPath('css/app.css')  // /app/public/css/app.css
/// ```
String publicPath([String relative = '']) {
  final root = Application.current.path('public');
  return relative.isEmpty ? root : p.join(root, relative);
}

/// The URL for a file in `public/`, for templates:
/// `asset('css/app.css')` gives `/css/app.css`.
///
/// Outside debug mode the URL carries a `?v=` token derived from the file's
/// size and modification time. This is Maat's stand-in for the content
/// hash Vite bakes into each filename: Tailwind's standalone CLI writes one
/// fixed output name, so the cache buster has to live in the query string.
///
/// Reads `app.asset_url` rather than the application, so it works in a
/// view test with nothing but a [Config]. Set that key to a CDN origin
/// in production and the path is appended to it unchanged.
String asset(String path) {
  final clean = path.startsWith('/') ? path.substring(1) : path;
  final base = config('app.asset_url') as String?;
  final origin = base == null || base.isEmpty
      ? ''
      : (base.endsWith('/') ? base.substring(0, base.length - 1) : base);
  return '$origin/$clean${_version(clean)}';
}

/// `?v=<token>`, or an empty string in debug mode, when the file is absent,
/// or when there is no booted [Application] to resolve `public/` against
/// (e.g. a unit test that only sets [Config.current]).
/// A stylesheet that 404s is visible but recoverable; throwing here would turn
/// every page of a not-yet-built checkout into a 500.
String _version(String relative) {
  if (config('app.debug') == true) return '';
  File file;
  try {
    file = File(publicPath(relative));
  } on StateError {
    return '';
  }
  if (!file.existsSync()) return '';
  final stat = file.statSync();
  final token = Object.hash(
    stat.modified.millisecondsSinceEpoch,
    stat.size,
  ).toUnsigned(32).toRadixString(16).padLeft(8, '0');
  return '?v=$token';
}
