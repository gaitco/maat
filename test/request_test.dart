import 'package:maat/maat.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  test('create with json body parses input', () {
    final r = Request.create(
      method: 'POST',
      path: '/api/posts?page=2',
      json: {
        'title': 'Hi',
        'meta': {'x': 1},
      },
    );
    expect(r.method, 'POST');
    expect(r.path, '/api/posts');
    expect(r.isJson, isTrue);
    expect(r.input('title'), 'Hi');
    expect(r.input('meta.x'), 1);
    expect(r.input('missing', 'd'), 'd');
    expect(r.query('page'), '2');
    expect(r.all(), {
      'page': '2',
      'title': 'Hi',
      'meta': {'x': 1},
    });
    expect(r.json, {
      'title': 'Hi',
      'meta': {'x': 1},
    });
  });

  test('json array body exposes json but empty input', () {
    final r = Request.create(method: 'POST', json: [1, 2]);
    expect(r.json, [1, 2]);
    expect(r.all(), isEmpty);
  });

  test('form body parses fields and [] arrays', () {
    final r = Request.create(
      method: 'POST',
      form: {'name': 'a b', 'tags[]': 'x'},
    );
    expect(r.input('name'), 'a b');
    expect(r.input('tags'), ['x']);
  });

  test('body wins over query in all(), input(null) returns all', () {
    final r = Request.create(path: '/?k=q', json: {'k': 'b'});
    expect(r.input('k'), 'b');
    expect(r.input(), {'k': 'b'});
  });

  test('headers are case-insensitive, bearerToken, wantsJson', () {
    final r = Request.create(
      path: '/web',
      headers: {'Authorization': 'Bearer abc', 'Accept': 'application/json'},
    );
    expect(r.header('authorization'), 'Bearer abc');
    expect(r.header('AUTHORIZATION'), 'Bearer abc');
    expect(r.bearerToken(), 'abc');
    expect(r.wantsJson, isTrue);
    expect(Request.create(path: '/api/x').wantsJson, isTrue);
    expect(Request.create(path: '/web').wantsJson, isFalse);
    expect(Request.create().bearerToken(), isNull);
  });

  test('only, except, has, filled, boolean, integer, string', () {
    final r = Request.create(
      json: {'a': 1, 'b': '', 'c': 'true', 'd': '12', 'e': null, 'f': []},
    );
    expect(r.only(['a', 'zz']), {'a': 1});
    expect(r.except(['a', 'b']), {'c': 'true', 'd': '12', 'e': null, 'f': []});
    expect(r.has('b'), isTrue);
    expect(r.has('zz'), isFalse);
    expect(r.filled('a'), isTrue);
    expect(r.filled('b'), isFalse);
    expect(r.filled('e'), isFalse);
    expect(r.filled('f'), isFalse);
    expect(r.boolean('c'), isTrue);
    expect(r.boolean('a'), isTrue);
    expect(r.boolean('b'), isFalse);
    expect(r.integer('d'), 12);
    expect(r.integer('c', 7), 7);
    expect(r.string('d'), '12');
  });

  test('merge and replace mutate input', () {
    final r = Request.create(json: {'a': 1});
    r.merge({'b': 2});
    expect(r.all(), {'a': 1, 'b': 2});
    r.replace({'z': 0});
    expect(r.all(), {'z': 0});
  });

  test('params and attributes bags', () {
    final r = Request.create();
    r.params = {'id': '5'};
    r.attributes['user'] = 'u';
    expect(r.param('id'), '5');
    expect(r.param('nope'), isNull);
    expect(r.attributes['user'], 'u');
  });

  test('fromShelf reads body once and captures method, uri, headers', () async {
    final s = shelf.Request(
      'PUT',
      Uri.parse('http://localhost:8000/items/1?x=1'),
      headers: {'content-type': 'application/json'},
      body: '{"n":1}',
    );
    final r = await Request.fromShelf(s);
    expect(r.method, 'PUT');
    expect(r.path, '/items/1');
    expect(r.query('x'), '1');
    expect(r.input('n'), 1);
    expect(r.rawBody, '{"n":1}');
    expect(r.ip, '127.0.0.1');
  });

  test('fromShelf rejects a body larger than the configured byte limit', () {
    final request = shelf.Request(
      'POST',
      Uri.parse('http://localhost/upload'),
      body: Stream<List<int>>.fromIterable([
        [1, 2],
        [3, 4],
      ]),
    );

    expect(
      Request.fromShelf(request, maxBodyBytes: 3),
      throwsA(
        isA<PayloadTooLargeHttpException>().having(
          (error) => error.statusCode,
          'statusCode',
          413,
        ),
      ),
    );
  });

  test(
    'fromShelfStream leaves the body unread and limits it while consumed',
    () async {
      var emitted = false;
      final shelfRequest = shelf.Request(
        'POST',
        Uri.parse('http://localhost/upload'),
        body: Stream<List<int>>.multi((controller) {
          emitted = true;
          controller
            ..add([1, 2])
            ..add([3, 4])
            ..close();
        }),
      );

      final request = Request.fromShelfStream(shelfRequest, maxBodyBytes: 3);

      expect(request.isBodyBuffered, isFalse);
      expect(emitted, isFalse);
      await expectLater(
        request.bodyStream.toList(),
        throwsA(isA<PayloadTooLargeHttpException>()),
      );
      expect(emitted, isTrue);
    },
  );

  group('publicUri', () {
    tearDown(() => Config.current = Config({}));

    Request forwarded({String ip = '127.0.0.1'}) => Request.create(
      path: '/api/tasks?page=2',
      ip: ip,
      headers: {'x-forwarded-proto': 'https', 'x-forwarded-host': 'todo.test'},
    );

    test('is the raw uri when no proxy is trusted', () {
      Config.current = Config({});
      final request = forwarded();
      expect(request.publicUri.scheme, 'http');
      expect(request.publicUri.host, 'localhost');
      expect(request.publicUri, request.uri);
    });

    test('honours the headers from a trusted proxy', () {
      Config.current = Config({
        'app': {'trusted_proxies': '127.0.0.1'},
      });
      final uri = forwarded().publicUri;
      expect(uri.scheme, 'https');
      expect(uri.host, 'todo.test');
      // No `:443` nobody wrote, and the query survives.
      expect(uri.toString(), 'https://todo.test/api/tasks?page=2');
    });

    test('a proxy that is not on the list is not trusted', () {
      Config.current = Config({
        'app': {'trusted_proxies': '10.0.0.1'},
      });
      expect(forwarded().publicUri.scheme, 'http');
    });

    test('a list and a wildcard both work', () {
      Config.current = Config({
        'app': {
          'trusted_proxies': ['10.0.0.1', '127.0.0.1'],
        },
      });
      expect(forwarded().publicUri.scheme, 'https');
      Config.current = Config({
        'app': {'trusted_proxies': '*'},
      });
      expect(forwarded(ip: '203.0.113.9').publicUri.scheme, 'https');
    });

    test('only the first hop of a forwarded chain is read', () {
      Config.current = Config({
        'app': {'trusted_proxies': '*'},
      });
      final request = Request.create(
        path: '/x',
        headers: {
          'x-forwarded-proto': 'https, http',
          'x-forwarded-host': 'todo.test:8443, evil.test',
        },
      );
      expect(request.publicUri.scheme, 'https');
      expect(request.publicUri.host, 'todo.test');
      expect(request.publicUri.port, 8443);
    });

    test('a nonsense proto is ignored rather than trusted', () {
      Config.current = Config({
        'app': {'trusted_proxies': '*'},
      });
      final request = Request.create(
        path: '/x',
        headers: {'x-forwarded-proto': 'javascript'},
      );
      expect(request.publicUri.scheme, 'http');
    });
  });
}
