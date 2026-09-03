import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('route_facade');
    await Application.configure(basePath: dir.path, environment: {}).create();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('verbs register on the app router with GET implying HEAD', () {
    Route.get('/a', (Request r) => 1);
    Route.post('/a', (Request r) => 1);
    Route.put('/a', (Request r) => 1);
    Route.patch('/a', (Request r) => 1);
    Route.delete('/a', (Request r) => 1);
    Route.options('/a', (Request r) => 1);
    Route.any('/b', (Request r) => 1);
    Route.match(['get', 'post'], '/c', (Request r) => 1);
    final methods = Route.router.routes.map((r) => r.methods).toList();
    expect(methods[0], ['GET', 'HEAD']);
    expect(methods[1], ['POST']);
    expect(
      methods[6],
      containsAll(['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']),
    );
    expect(methods[7], ['GET', 'POST']);
  });

  test('group with named args before the body', () {
    Route.group(prefix: 'admin', middleware: ['auth'], name: 'admin.', () {
      Route.get('users', (Request r) => 1).name('users');
    });
    final route = Route.router.routes.single;
    expect(route.uri, '/admin/users');
    expect(route.middlewareList, ['auth']);
    expect(route.routeName, 'admin.users');
  });

  test('fluent builder', () {
    Route.prefix('api').middleware(['a']).name('api.').group(() {
      Route.middleware(['b']).group(() {
        Route.get('x', (Request r) => 1).name('x');
      });
    });
    final route = Route.router.routes.single;
    expect(route.uri, '/api/x');
    expect(route.middlewareList, ['a', 'b']);
    expect(route.routeName, 'api.x');
  });

  test('resource, fallback and route() helper', () {
    Route.resource('posts', _Ctrl(), only: ['show']);
    Route.fallback((Request r) => 'fb');
    expect(route('posts.show', {'id': 4}), '/posts/4');
    expect(Route.router.match('GET', '/nothing').route.uri, '/{fallback?}');
  });
}

class _Ctrl extends ResourceController {
  @override
  Object? show(Request request, String id) => id;
}
