import 'dart:async';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../request.dart';
import '../response.dart';
import 'middleware.dart';

/// Serves files from the application's `public/` directory, the way nginx
/// does in front of a Laravel application.
///
/// Register it as global middleware so it answers before routing: a
/// request that names a real file short-circuits, and everything else
/// falls through to the router untouched. Only `GET` and `HEAD` are
/// served — a `POST /css/app.css` belongs to the router, not here.
///
/// File bodies are streamed from disk. In production a web server or CDN is
/// still preferable for caching and range requests, as it is for Laravel.
class PublicFiles extends Middleware {
  PublicFiles(String root, {this.maxAge = const Duration(hours: 1)})
    : root = p.canonicalize(root);

  /// The directory as it was configured. Containment is checked against
  /// [_realRoot], not against this.
  final String root;

  /// `cache-control: public, max-age=…`. Zero omits the header, which is
  /// what you want while developing an asset pipeline.
  final Duration maxAge;

  @override
  FutureOr<Response> handle(Request request, Next next) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return next(request);
    }
    final file = _resolve(request);
    if (file == null) return next(request);

    final stat = file.statSync();
    final modified = stat.modified.toUtc();
    if (_notModifiedSince(request.header('if-modified-since'), modified)) {
      return Response('', status: 304, headers: _headers(file, modified));
    }
    final headers = {
      ..._headers(file, modified),
      'content-length': '${stat.size}',
    };
    return request.method == 'HEAD'
        ? Response.bytes(const [], headers: headers)
        : Response.stream(file.openRead(), headers: headers);
  }

  Map<String, String> _headers(File file, DateTime modified) => {
    'content-type': lookupMimeType(file.path) ?? 'application/octet-stream',
    'last-modified': _httpDate(modified),
    if (maxAge > Duration.zero)
      'cache-control': 'public, max-age=${maxAge.inSeconds}',
  };

  /// The file this request names, or null when it names none — which is
  /// every case the router should get a look at, including a directory,
  /// a missing file, and anything that tried to escape [root].
  ///
  /// Traversal is stopped by canonicalising the candidate and checking it
  /// is still inside [root], not by looking for `..` in the request. Two
  /// findings make that the only defensible order:
  ///
  /// * `Uri.pathSegments` percent-decodes each segment, so `%2f` arrives
  ///   as a real separator: `/..%2f..%2fetc/passwd` yields the single
  ///   segment `../../etc`. A scan for a `..` *segment* never sees it;
  ///   joining and normalising turns it into `/etc/passwd`, which the
  ///   containment check then rejects.
  /// * A symlink inside `public/` can point anywhere, so containment is
  ///   checked again after the link is resolved.
  File? _resolve(Request request) {
    final base = _realRoot;
    if (base == null) return null;
    final segments = request.uri.pathSegments;
    if (segments.isEmpty) return null;
    // `%00` decodes to a real NUL, which truncates the path for the OS
    // but not for the Dart string holding it: a request for
    // `app.css\u0000.txt` would satisfy an extension check and then open
    // a different file. Spelled as an escape; a literal NUL in source is
    // invisible in every editor that would have to review this line.
    if (segments.any((s) => s.contains('\u0000'))) return null;

    final candidate = p.canonicalize(p.join(base, p.joinAll(segments)));
    if (!p.isWithin(base, candidate)) return null;

    final file = File(candidate);
    if (!file.existsSync()) return null;

    final real = p.canonicalize(file.resolveSymbolicLinksSync());
    if (!p.isWithin(base, real)) return null;
    // `existsSync` follows links, so a link to a directory lands here.
    return FileSystemEntity.isFileSync(real) ? File(real) : null;
  }

  /// [root] as the filesystem sees it, or null when it does not exist.
  ///
  /// Resolved per request rather than once at construction for two
  /// reasons. `public/` may not exist when the application boots — an
  /// asset pipeline creates it — and a root captured before then would
  /// never match. And `p.canonicalize` normalises text only: a root
  /// reached through a symlinked ancestor (macOS spells its temporary
  /// directories `/var/...` for `/private/var/...`, and a container
  /// volume or a mounted home does the same) would never contain the
  /// *resolved* path of the files inside it, so every single request
  /// would fall through to the router. It costs one `stat` next to a
  /// file read.
  String? get _realRoot {
    try {
      return p.canonicalize(Directory(root).resolveSymbolicLinksSync());
    } on FileSystemException {
      return null;
    }
  }

  /// RFC 9110 `If-Modified-Since`: HTTP dates have one-second resolution,
  /// so a file written in the same second as the header must still count
  /// as unmodified, or every request re-sends it.
  bool _notModifiedSince(String? header, DateTime modified) {
    if (header == null) return false;
    try {
      final since = HttpDate.parse(header);
      return !modified.isAfter(since.add(const Duration(seconds: 1)));
    } on HttpException {
      // A header any client may send malformed must not become a 500.
      return false;
    } on FormatException {
      return false;
    }
  }

  String _httpDate(DateTime value) => HttpDate.format(value);
}
