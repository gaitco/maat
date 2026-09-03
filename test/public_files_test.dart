import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Bytes no UTF-8 decoder can round-trip: if any layer turns the body
/// into a Dart string and back, these change.
const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFE, 0x00];

void main() {
  late Directory root;
  late Directory outside;
  late PublicFiles files;

  /// What the router would have returned; every request that reaches it
  /// is one [PublicFiles] declined to serve.
  Future<Response> serve(Request request) async =>
      files.handle(request, (r) => Response.text('router', status: 404));

  setUp(() {
    root = Directory.systemTemp.createTempSync('public_');
    outside = Directory.systemTemp.createTempSync('secret_');
    File(p.join(outside.path, 'passwd')).writeAsStringSync('root:x:0:0');
    Directory(p.join(root.path, 'css')).createSync();
    File(
      p.join(root.path, 'css', 'app.css'),
    ).writeAsStringSync('.a{color:red}');
    Directory(p.join(root.path, 'img')).createSync();
    File(p.join(root.path, 'img', 'pixel.png')).writeAsBytesSync(_png);
    files = PublicFiles(root.path);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  group('serving', () {
    test('serves a file with its content type and length', () async {
      final response = await serve(Request.create(path: '/css/app.css'));
      expect(response.statusCode, 200);
      expect(response.isStreaming, isTrue);
      expect(await response.toShelf().readAsString(), '.a{color:red}');
      expect(response.headers['content-type'], 'text/css');
      expect(response.headers['content-length'], '13');
      expect(response.headers['cache-control'], 'public, max-age=3600');
    });

    test('binary files survive byte for byte', () async {
      final response = await serve(Request.create(path: '/img/pixel.png'));
      expect(response.headers['content-type'], 'image/png');
      final shelfResponse = response.toShelf();
      expect(
        await shelfResponse.read().expand((chunk) => chunk).toList(),
        _png,
      );
      expect(shelfResponse.contentLength, _png.length);
    });

    test('HEAD sends the headers and no body', () async {
      final response = await serve(
        Request.create(method: 'HEAD', path: '/css/app.css'),
      );
      expect(response.statusCode, 200);
      expect(response.encodedBody, '');
      expect(response.headers['content-length'], '13');
    });

    test('maxAge zero omits cache-control', () async {
      files = PublicFiles(root.path, maxAge: Duration.zero);
      final response = await serve(Request.create(path: '/css/app.css'));
      expect(response.headers.containsKey('cache-control'), isFalse);
    });

    test('an unmodified file gets a 304 with no body', () async {
      final first = await serve(Request.create(path: '/css/app.css'));
      final response = await serve(
        Request.create(
          path: '/css/app.css',
          headers: {'if-modified-since': first.headers['last-modified']!},
        ),
      );
      expect(response.statusCode, 304);
      expect(response.encodedBody, '');
      expect(response.headers.containsKey('content-length'), isFalse);
    });

    test('an unparseable if-modified-since sends the file', () async {
      final response = await serve(
        Request.create(
          path: '/css/app.css',
          headers: {'if-modified-since': 'yesterday'},
        ),
      );
      expect(response.statusCode, 200);
    });
  });

  group('falling through to the router', () {
    Future<void> expectFallsThrough(Request request) async {
      final response = await serve(request);
      expect(response.encodedBody, 'router', reason: request.uri.toString());
      expect(response.statusCode, 404);
    }

    test(
      'a missing file',
      () => expectFallsThrough(Request.create(path: '/nope.css')),
    );

    test('the root path', () => expectFallsThrough(Request.create(path: '/')));

    test('a directory', () => expectFallsThrough(Request.create(path: '/css')));

    test('a method the router owns', () async {
      await expectFallsThrough(
        Request.create(method: 'POST', path: '/css/app.css'),
      );
      await expectFallsThrough(
        Request.create(method: 'DELETE', path: '/css/app.css'),
      );
    });

    test('a missing public directory falls through to the router', () async {
      // What an `--api` project ships: no public/ directory at all.
      // `_realRoot` catches the FileSystemException and returns null.
      files = PublicFiles(p.join(root.path, 'no-such-public-dir'));
      await expectFallsThrough(Request.create(path: '/css/app.css'));
    });
  });

  group('traversal', () {
    Future<void> expectRefused(String path) async {
      final response = await serve(Request.create(path: path));
      expect(response.encodedBody, 'router', reason: path);
      expect(response.encodedBody, isNot(contains('root:x:0:0')), reason: path);
    }

    test('plain dot-dot cannot climb out', () async {
      await expectRefused('/../${p.basename(outside.path)}/passwd');
      await expectRefused('/css/../../${p.basename(outside.path)}/passwd');
    });

    test('an encoded separator cannot climb out', () async {
      // The one a `..`-segment scan misses: Uri.pathSegments decodes %2f,
      // so this arrives as the single segment `../../<dir>` — which only
      // normalising and then checking containment catches.
      final dir = p.basename(outside.path);
      await expectRefused('/..%2f..%2f$dir/passwd');
      await expectRefused('/%2e%2e%2f%2e%2e%2f$dir%2fpasswd');
    });

    test('an absolute path is taken as relative to the root', () async {
      await expectRefused('//etc/passwd');
      await expectRefused('/${p.join(outside.path, 'passwd')}');
    });

    test('a NUL in the path is refused', () async {
      await expectRefused('/css/app.css%00.txt');
      await expectRefused('/css/%00app.css');
    });

    test('a symlink out of the root is refused', () async {
      final link = Link(p.join(root.path, 'escape'));
      link.createSync(p.join(outside.path, 'passwd'));
      await expectRefused('/escape');
    });

    test('a symlink inside the root is served', () async {
      final link = Link(p.join(root.path, 'alias.css'));
      link.createSync(p.join(root.path, 'css', 'app.css'));
      final response = await serve(Request.create(path: '/alias.css'));
      expect(response.statusCode, 200);
      expect(await response.toShelf().readAsString(), '.a{color:red}');
    });
  });

  group('asset()', () {
    test('gives a root-relative URL by default', () {
      Config.current = Config({});
      expect(asset('css/app.css'), '/css/app.css');
      expect(asset('/css/app.css'), '/css/app.css');
    });

    test('prefixes app.asset_url when one is set', () {
      Config.current = Config({
        'app': {'asset_url': 'https://cdn.example.com/'},
      });
      expect(asset('css/app.css'), 'https://cdn.example.com/css/app.css');
      Config.current = Config({});
    });
  });
}
