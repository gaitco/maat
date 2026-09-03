import 'package:maat/maat.dart';
import 'package:test/test.dart';

class PostController extends ResourceController {
  @override
  Object? index(Request request) => 'index';
  @override
  Object? show(Request request, String id) => 'show $id';
}

void main() {
  late Router router;
  setUp(() => router = Router());

  group('matching', () {
    test('static path and method', () {
      router.add(['GET'], '/posts', (Request r) => 'ok');
      final m = router.match('GET', '/posts');
      expect(m.params, isEmpty);
      expect(m.route.uri, '/posts');
    });

    test('HEAD matches GET, trailing slash ignored, root works', () {
      router.add(['GET'], '/', (Request r) => 'root');
      router.add(['GET'], '/posts', (Request r) => 'ok');
      expect(router.match('HEAD', '/posts/').route.uri, '/posts');
      expect(router.match('GET', '/').route.uri, '/');
      expect(router.match('GET', '').route.uri, '/');
    });

    test('params, optional params, where constraints', () {
      router.add(['GET'], '/posts/{id}', (Request r, String id) => id);
      router.add(
        ['GET'],
        '/files/{path?}',
        (Request r, [String? path]) => path,
      );
      router
          .add(['GET'], '/nums/{n}', (Request r, String n) => n)
          .where('n', r'\d+');
      expect(router.match('GET', '/posts/7').params, {'id': '7'});
      expect(router.match('GET', '/files').params, isEmpty);
      expect(router.match('GET', '/files/a.txt').params, {'path': 'a.txt'});
      expect(router.match('GET', '/nums/12').params, {'n': '12'});
      expect(
        () => router.match('GET', '/nums/ab'),
        throwsA(isA<NotFoundHttpException>()),
      );
    });

    test('first registered wins', () {
      router.add(['GET'], '/posts/{id}', (Request r, String id) => 'param');
      router.add(['GET'], '/posts/new', (Request r) => 'static');
      expect(router.match('GET', '/posts/new').params, {'id': 'new'});
    });

    test(
      '404 when nothing matches, 405 with allow header when path exists',
      () {
        router.add(['GET'], '/a', (Request r) => 1);
        router.add(['POST'], '/a', (Request r) => 2);
        expect(
          () => router.match('GET', '/zzz'),
          throwsA(isA<NotFoundHttpException>()),
        );
        expect(
          () => router.match('DELETE', '/a'),
          throwsA(
            isA<MethodNotAllowedHttpException>().having(
              (e) => e.headers['allow'],
              'allow',
              'GET, POST',
            ),
          ),
        );
      },
    );

    test('fallback route catches unmatched paths', () {
      router.fallback((Request r) => 'fb');
      expect(router.match('GET', '/anything/at/all').route.handler, isNotNull);
    });
  });

  group('groups', () {
    test('prefix, middleware and name prefix nest', () {
      router.group(prefix: 'api', middleware: ['a'], name: 'api.', () {
        router.group(prefix: '/v1/', middleware: ['b'], () {
          router
              .add(['GET'], 'users', (Request r) => 1)
              .middleware(['c'])
              .name('users');
        });
      });
      final route = router.routes.single;
      expect(route.uri, '/api/v1/users');
      expect(route.middlewareList, ['a', 'b', 'c']);
      expect(route.routeName, 'api.users');
      expect(router.match('GET', '/api/v1/users').route, same(route));
    });
  });

  group('names and urls', () {
    test(
      'url substitutes params, drops absent optional, appends extras as query',
      () {
        router
            .add(
              ['GET'],
              '/posts/{id}/{slug?}',
              (Request r, String id, [String? slug]) => 1,
            )
            .name('posts.show');
        expect(router.url('posts.show', {'id': 3}), '/posts/3');
        expect(
          router.url('posts.show', {'id': 3, 'slug': 'hi'}),
          '/posts/3/hi',
        );
        expect(
          router.url('posts.show', {'id': 3, 'page': 2}),
          '/posts/3?page=2',
        );
        expect(() => router.url('posts.show'), throwsArgumentError);
        expect(() => router.url('nope'), throwsArgumentError);
        expect(router.hasNamed('posts.show'), isTrue);
      },
    );

    test('duplicate names fail fast', () {
      router.add(['GET'], '/a', (Request r) => 1).name('x');
      expect(
        () => router.add(['GET'], '/b', (Request r) => 1).name('x'),
        throwsStateError,
      );
    });
  });

  group('resource', () {
    test('registers the five api routes with names', () {
      router.resource('posts', PostController());
      final uris = router.routes
          .map((r) => '${r.methods.first} ${r.uri}')
          .toList();
      expect(uris, [
        'GET /posts',
        'POST /posts',
        'GET /posts/{id}',
        'PUT /posts/{id}',
        'DELETE /posts/{id}',
      ]);
      expect(router.routes.map((r) => r.routeName), [
        'posts.index',
        'posts.store',
        'posts.show',
        'posts.update',
        'posts.destroy',
      ]);
      expect(router.routes[3].methods, ['PUT', 'PATCH']);
    });

    test('only and except', () {
      router.resource('a', PostController(), only: ['index']);
      router.resource('b', PostController(), except: ['destroy', 'update']);
      expect(router.routes.map((r) => r.routeName), [
        'a.index',
        'b.index',
        'b.store',
        'b.show',
      ]);
    });

    test('default ResourceController methods throw 404', () async {
      final ctrl = PostController();
      expect(
        () => ctrl.store(Request.create()),
        throwsA(isA<NotFoundHttpException>()),
      );
    });
  });

  group('run', () {
    test('passes params positionally by handler arity', () async {
      router.add(
        ['GET'],
        '/a/{x}/{y}',
        (Request r, String x, String y) => '$x-$y',
      );
      router.add(['GET'], '/b/{x}/{y}', (Request r, String x) => x);
      router.add(['GET'], '/c/{x}', (Request r) => r.param('x'));
      router.add(['GET'], '/d', () => 'zero');
      router.add(['GET'], '/e/{x}', (r, x) => 'dyn $x');
      Future<Object?> call(String path) async {
        final m = router.match('GET', path);
        final req = Request.create(path: path)
          ..params = m.params
          ..route = m.route;
        return m.route.run(req);
      }

      expect(await call('/a/1/2'), '1-2');
      expect(await call('/b/1/2'), '1');
      expect(await call('/c/9'), '9');
      expect(await call('/d'), 'zero');
      expect(await call('/e/5'), 'dyn 5');
    });

    test('absent optional param is not passed', () async {
      router.add(['GET'], '/f/{x?}', (Request r, [String? x]) => x ?? 'none');
      final m = router.match('GET', '/f');
      expect(
        await m.route.run(Request.create(path: '/f')..params = m.params),
        'none',
      );
    });

    test('handler with an unsupported signature fails at registration', () {
      expect(
        () => router.add(['GET'], '/g/{x}', (Request r, int x) => x),
        throwsArgumentError,
      );
    });
  });
}
