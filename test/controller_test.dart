import 'dart:async';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

class Tag extends Middleware {
  Tag(this.name);
  final String name;
  @override
  FutureOr<Response> handle(Request request, Next next) async =>
      (await next(request)).header('x-$name', '1');
}

class PostController extends ResourceController {
  @override
  List<Object> middleware() => [
    Tag('all'),
    ControllerMiddleware(Tag('read'), only: [index, show]),
    ControllerMiddleware(Tag('write'), except: [index, show]),
  ];

  @override
  Object? index(Request request) => 'index';
  @override
  Object? show(Request request, String id) => 'show $id';
  @override
  Object? store(Request request) => 'store';
}

class ShowProfile extends Controller {
  @override
  List<Object> middleware() => [Tag('profile')];

  Object? call(Request request, [String? id]) => 'profile ${id ?? 'me'}';
}

class NotInvokable extends Controller {}

void main() {
  late Directory dir;
  late Application app;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('controller');
    app = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, String> headersOf(TestResponse r) => r.headers;

  group('controller middleware', () {
    test('Route.resource applies middleware per action', () async {
      Route.resource('posts', PostController());
      final client = TestClient(app);
      final index = await client.get('/posts');
      index.assertOk();
      expect(headersOf(index), containsPair('x-all', '1'));
      expect(headersOf(index), containsPair('x-read', '1'));
      expect(headersOf(index).containsKey('x-write'), isFalse);

      final store = await client.postJson('/posts', {});
      expect(headersOf(store), containsPair('x-all', '1'));
      expect(headersOf(store), containsPair('x-write', '1'));
      expect(headersOf(store).containsKey('x-read'), isFalse);
    });

    test('Route.controller(...).group applies it to tear-offs', () async {
      final posts = PostController();
      Route.controller(posts).group(() {
        Route.get('/latest', posts.index);
        Route.post('/drafts', posts.store);
        Route.get('/plain', (Request r) => 'not an action');
      });
      final client = TestClient(app);
      expect(
        headersOf(await client.get('/latest')),
        containsPair('x-read', '1'),
      );
      expect(
        headersOf(await client.postJson('/drafts', {})),
        containsPair('x-write', '1'),
      );
      final plain = headersOf(await client.get('/plain'));
      expect(plain, containsPair('x-all', '1'));
      expect(plain.containsKey('x-read'), isFalse);
    });

    test('a bare tear-off outside a controller group gets none', () async {
      Route.get('/latest', PostController().index);
      final r = await TestClient(app).get('/latest');
      r.assertOk();
      expect(headersOf(r).containsKey('x-all'), isFalse);
    });

    test('order: group, controller, then route middleware', () {
      final posts = PostController();
      Route.middleware(['a']).controller(posts).group(() {
        Route.get('/x', posts.index).middleware(['z']);
      });
      final list = Route.router.routes.single.middlewareList;
      expect(list.first, 'a');
      expect(list.last, 'z');
      expect(list.whereType<Tag>().map((t) => t.name), ['all', 'read']);
    });
  });

  group('single-action controllers', () {
    test('an object with call() is a handler', () async {
      Route.get('/profile', ShowProfile());
      Route.get('/profile/{id}', ShowProfile());
      final client = TestClient(app);
      final me = await client.get('/profile');
      me.assertOk();
      expect(me.body, 'profile me');
      expect(headersOf(me), containsPair('x-profile', '1'));
      expect((await client.get('/profile/7')).body, 'profile 7');
    });

    test('a controller without call() is rejected at registration', () {
      expect(() => Route.get('/x', NotInvokable()), throwsArgumentError);
    });

    test('other objects are rejected', () {
      expect(() => Route.get('/x', 42), throwsArgumentError);
    });
  });
}
