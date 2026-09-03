import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late TestClient client;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('tc');
    final application = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    Route.get(
      '/api/ping',
      (Request r) => {
        'pong': true,
        'auth': r.bearerToken(),
        'h': r.header('x-a'),
      },
    );
    Route.post(
      '/api/items',
      (Request r) async => Response.json(
        await r.validate({'name': 'required', 'qty': 'integer'}),
        status: 201,
      ),
    );
    Route.post('/form', (Request r) => r.all());
    Route.get('/go', (Request r) => Response.redirect('/there'));
    Route.delete('/api/items/{id}', (Request r, String id) => null);
    Route.get('/page', (Request r) => '<h1>Hello</h1>');
    Route.get('/raw-map', (Request r) => Response({'a': 1, 'b': 2}));
    Route.get(
      '/stream-response',
      (Request r) => Response.stream(
        Stream.fromIterable([
          [104, 101, 108],
          [108, 111],
        ]),
        headers: {'content-type': 'text/plain'},
      ),
    );
    Route.get('/secure', (Request r) => throw UnauthorizedHttpException());
    Route.get('/vip', (Request r) => throw ForbiddenHttpException());
    client = TestClient(application);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('get with headers and token', () async {
    final res = await client
        .withToken('t0k')
        .withHeader('X-A', 'a')
        .get('/api/ping');
    res
        .assertOk()
        .assertJson({'pong': true})
        .assertJsonPath('auth', 't0k')
        .assertJsonPath('h', 'a')
        .assertHeaderContains('content-type', 'json');
    expect(res.json, {'pong': true, 'auth': 't0k', 'h': 'a'});
  });

  test('postJson success and validation errors', () async {
    (await client.postJson('/api/items', {
      'name': 'x',
      'qty': 2,
    })).assertCreated().assertJson({'name': 'x'});
    final bad = await client.postJson('/api/items', {'qty': 'no'});
    bad
        .assertUnprocessable()
        .assertJsonValidationErrors(['name', 'qty'])
        .assertJsonPath('errors.name.0', 'The name field is required.');
    (await client.postJson('/api/items', {
      'name': 'x',
    })).assertJsonMissingValidationErrors(['qty']);
  });

  test('form post, delete, redirect, see', () async {
    (await client.post(
      '/form',
      form: {'a': '1'},
    )).assertOk().assertJson({'a': '1'});
    (await client.delete('/api/items/4')).assertNoContent();
    (await client.get('/go')).assertRedirect('/there');
    (await client.get('/page')).assertOk().assertSee('Hello');
    (await client.get('/missing')).assertNotFound();
  });

  test('failed assertions throw with a helpful message', () async {
    final res = await client.get('/api/ping');
    expect(
      () => res.assertStatus(500),
      throwsA(
        isA<TestClientAssertionError>().having(
          (e) => e.toString(),
          'msg',
          contains('Expected status 500 but got 200'),
        ),
      ),
    );
    expect(
      () => res.assertJson({'pong': false}),
      throwsA(isA<TestClientAssertionError>()),
    );
    expect(
      () => res.assertJsonPath('nope', 1),
      throwsA(isA<TestClientAssertionError>()),
    );
  });

  test('bare Response(map) is JSON-encoded with a JSON content type, agreeing '
      'with what production sends via toShelf', () async {
    final res = await client.get('/raw-map');
    expect(res.json, {'a': 1, 'b': 2});
    final production = Response({'a': 1, 'b': 2}).toShelf();
    expect(res.headers['content-type'], contains('application/json'));
    expect(res.headers['content-type'], production.headers['content-type']);
    expect(res.body, await production.readAsString());
  });

  test('streamed responses can be asserted through TestClient', () async {
    final res = await client.get('/stream-response');
    res.assertOk().assertSee('hello');
    expect(res.headers['content-type'], 'text/plain');
  });

  test('assertUnauthorized and assertForbidden', () async {
    (await client.get('/secure')).assertUnauthorized();
    (await client.get('/vip')).assertForbidden();
    final unauthorized = await client.get('/secure');
    expect(
      () => unauthorized.assertForbidden(),
      throwsA(isA<TestClientAssertionError>()),
    );
  });

  test(
    'JSON assertions on a non-JSON body throw TestClientAssertionError, not FormatException',
    () async {
      final res = await client.get('/page');
      expect(() => res.json, throwsA(isA<TestClientAssertionError>()));
      expect(
        () => res.assertJson({'a': 1}),
        throwsA(isA<TestClientAssertionError>()),
      );
    },
  );

  test(
    'assertJson distinguishes an absent key from a present null value',
    () async {
      final res = await client.get('/api/ping');
      expect(
        () => res.assertJson({'zzz': null}),
        throwsA(
          isA<TestClientAssertionError>().having(
            (e) => e.toString(),
            'msg',
            contains('key is missing'),
          ),
        ),
      );
    },
  );

  test(
    'a string middleware alias is memoized across requests through the kernel, '
    'so throttle:2,1 actually rate-limits',
    () async {
      final throttleDir = Directory.systemTemp.createTempSync('tc-throttle');
      addTearDown(() => throttleDir.deleteSync(recursive: true));
      final throttleApp =
          await Application.configure(
                basePath: throttleDir.path,
                environment: {},
              )
              .withMiddleware(
                (m) => m.alias({'throttle': ThrottleRequests.factory}),
              )
              .create();
      Route.get('/limited', (Request r) => 'ok').middleware(['throttle:2,1']);
      final throttleClient = TestClient(throttleApp);

      expect((await throttleClient.get('/limited')).statusCode, 200);
      expect((await throttleClient.get('/limited')).statusCode, 200);
      expect((await throttleClient.get('/limited')).statusCode, 429);
    },
  );
}
