import 'dart:convert';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Object? handler(Request request) => null;
Object? handlerWithId(Request request, String id) => null;

final bookSchema = ApiSchema.object({
  'id': ApiSchema.integer(),
  'title': ApiSchema.string(),
  'subtitle': ApiSchema.string().nullable,
  'published_at': ApiSchema.string(format: 'date-time'),
}, name: 'Book');

void registerRoutes() {
  Route.get('/api/books', handler)
      .name('books.index')
      .summary('List books')
      .query({'q': 'string|max:50'})
      .responds(ApiSchema.array(bookSchema));
  Route.post('/api/books', handler)
      .name('books.store')
      .middleware(['auth:cartouche'])
      .body({'title': 'required|string|max:120', 'subtitle': 'nullable|string'})
      .responds(bookSchema, status: 201);
  Route.get('/api/books/{id}', handlerWithId)
      .name('books.show')
      .params({'id': 'required|integer'})
      .responds(bookSchema)
      .responds(apiErrorSchema, status: 404);
  Route.delete('/api/books/{id}', handlerWithId)
      .name('books.destroy')
      .middleware(['auth:cartouche'])
      .params({'id': 'required|integer'})
      .responds(const ApiSchema.none(), status: 204);
}

void main() {
  late Directory dir;
  late Sesh maat;
  late StringBuffer out;
  late StringBuffer err;

  Future<void> boot({
    Map<String, dynamic> config = const {},
    bool routes = true,
  }) async {
    final app = await Application.configure(basePath: dir.path, environment: {})
        .withConfig({
          'app': {'name': 'Catalog'},
          ...config,
        })
        .create();
    if (routes) registerRoutes();
    out = StringBuffer();
    err = StringBuffer();
    maat = Sesh(app, out: out, err: err);
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('api'));
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String relative) =>
      File(p.join(dir.path, relative)).readAsStringSync();

  group('api:openapi', () {
    test('writes a document built from the route contracts', () async {
      await boot();

      expect(await maat.run(['api:openapi']), 0);

      final json = jsonDecode(read('openapi.json')) as Map<String, Object?>;
      expect(json['openapi'], '3.1.0');
      expect((json['info']! as Map)['title'], 'Catalog');
      expect((json['paths']! as Map).keys, ['/api/books', '/api/books/{id}']);
      expect(out.toString(), contains('4 operations'));
    });

    test('reads title, version, description and servers from config', () async {
      await boot(
        config: {
          'api': {
            'title': 'Catalog API',
            'version': '2.1.0',
            'description': 'Books and their authors.',
            'servers': [
              'https://catalog.test',
              {'url': 'http://localhost:8000', 'description': 'Local'},
            ],
          },
        },
      );

      expect(await maat.run(['api:openapi']), 0);

      final json = jsonDecode(read('openapi.json')) as Map<String, Object?>;
      expect(json['info'], {
        'title': 'Catalog API',
        'description': 'Books and their authors.',
        'version': '2.1.0',
      });
      expect(json['servers'], [
        {'url': 'https://catalog.test'},
        {'url': 'http://localhost:8000', 'description': 'Local'},
      ]);
    });

    test('--output=- writes to stdout instead of a file', () async {
      await boot();

      expect(await maat.run(['api:openapi', '--output=-']), 0);

      expect(out.toString(), startsWith('{\n  "openapi": "3.1.0"'));
      expect(File(p.join(dir.path, 'openapi.json')).existsSync(), isFalse);
    });

    test('running it twice produces identical bytes', () async {
      await boot();
      expect(await maat.run(['api:openapi', '--output=first.json']), 0);
      expect(await maat.run(['api:openapi', '--output=second.json']), 0);

      expect(read('first.json'), read('second.json'));
    });

    test(
      'an application with no contracts fails with an explanation',
      () async {
        await boot(routes: false);
        Route.get('/', handler);

        expect(await maat.run(['api:openapi']), 1);
        expect(err.toString(), contains('No route declares an API contract'));
        expect(File(p.join(dir.path, 'openapi.json')).existsSync(), isFalse);
      },
    );
  });

  group('api:client', () {
    test('writes a typed client at the default path', () async {
      await boot();

      expect(await maat.run(['api:client']), 0);

      final source = read('lib/api/api_client.dart');
      expect(source, contains('final class ApiClient {'));
      expect(source, contains('final class BookDto {'));
      expect(source, contains('Future<List<BookDto>> booksIndex({String? q})'));
      expect(source, contains('Future<void> booksDestroy({required int id})'));
      expect(out.toString(), contains('4 methods'));
    });

    test('--output and --class are honoured', () async {
      await boot();

      expect(
        await maat.run([
          'api:client',
          '--output=lib/catalog.dart',
          '--class=CatalogApi',
        ]),
        0,
      );

      expect(read('lib/catalog.dart'), contains('final class CatalogApi {'));
    });

    test(
      'the generated client analyzes and is already formatted',
      () async {
        await boot();
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: generated_client
environment:
  sdk: ^3.12.0
dependencies:
  horus_client:
    path: ${p.normalize(p.join(Directory.current.path, '..', 'horus_client'))}
''');

        expect(await maat.run(['api:client']), 0);

        final pubGet = await Process.run('dart', [
          'pub',
          'get',
        ], workingDirectory: dir.path);
        expect(pubGet.exitCode, 0, reason: pubGet.stderr.toString());

        final analyze = await Process.run('dart', [
          'analyze',
          '--fatal-infos',
        ], workingDirectory: dir.path);
        expect(
          analyze.exitCode,
          0,
          reason: '${analyze.stdout}${analyze.stderr}',
        );

        // Generated code lands in a repository already tidy, so a later
        // `dart format .` never shows up as an unrelated diff.
        final format = await Process.run('dart', [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          '.',
        ], workingDirectory: dir.path);
        expect(format.exitCode, 0, reason: '${format.stdout}${format.stderr}');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an application with no contracts fails with an explanation',
      () async {
        await boot(routes: false);

        expect(await maat.run(['api:client']), 1);
        expect(err.toString(), contains('No route declares an API contract'));
      },
    );
  });
}
