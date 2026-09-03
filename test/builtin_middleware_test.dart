import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  group('TrimStrings', () {
    test('trims strings recursively, leaves other types', () async {
      final req = Request.create(
        json: {
          'a': '  x ',
          'n': {
            'b': ' y',
            'l': [' z ', 1],
          },
          'i': 2,
        },
      );
      await TrimStrings().handle(req, (r) => Response.text('ok'));
      expect(req.all(), {
        'a': 'x',
        'n': {
          'b': 'y',
          'l': ['z', 1],
        },
        'i': 2,
      });
    });
  });

  group('Cors', () {
    final cors = Cors(
      options: {
        'allowed_origins': ['https://app.test'],
        'allowed_methods': ['GET', 'POST'],
        'allowed_headers': ['content-type'],
        'exposed_headers': ['x-id'],
        'max_age': 600,
        'supports_credentials': true,
      },
    );

    test('preflight returns 204 with cors headers', () async {
      final req = Request.create(
        method: 'OPTIONS',
        path: '/x',
        headers: {
          'origin': 'https://app.test',
          'access-control-request-method': 'POST',
        },
      );
      final res = await cors.handle(
        req,
        (r) => Response.text('should not run'),
      );
      expect(res.statusCode, 204);
      expect(res.headers['access-control-allow-origin'], 'https://app.test');
      expect(res.headers['access-control-allow-methods'], 'GET, POST');
      expect(res.headers['access-control-allow-headers'], 'content-type');
      expect(res.headers['access-control-max-age'], '600');
      expect(res.headers['access-control-allow-credentials'], 'true');
      expect(res.headers['vary'], 'Origin');
    });

    test('normal request gets origin and exposed headers', () async {
      final req = Request.create(
        path: '/x',
        headers: {'origin': 'https://app.test'},
      );
      final res = await cors.handle(req, (r) => Response.text('ok'));
      expect(res.body, 'ok');
      expect(res.headers['access-control-allow-origin'], 'https://app.test');
      expect(res.headers['access-control-expose-headers'], 'x-id');
    });

    test('disallowed origin gets no cors headers', () async {
      final req = Request.create(
        path: '/x',
        headers: {'origin': 'https://evil.test'},
      );
      final res = await cors.handle(req, (r) => Response.text('ok'));
      expect(res.headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('wildcard defaults and path filter', () async {
      final wild = Cors(
        options: {
          'paths': ['api/*'],
        },
      );
      final hit = await wild.handle(
        Request.create(path: '/api/a', headers: {'origin': 'http://a'}),
        (r) => Response.text('ok'),
      );
      expect(hit.headers['access-control-allow-origin'], '*');
      final miss = await wild.handle(
        Request.create(path: '/web', headers: {'origin': 'http://a'}),
        (r) => Response.text('ok'),
      );
      expect(miss.headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('reads config("cors") when no options given', () async {
      // `Config.current` is a mutable static, so leaving it set would leak into
      // every later test in this file. Restored on the way out rather than in a
      // group-level tearDown, so the blast radius stays next to the mutation.
      final previousConfig = Config.current;
      addTearDown(() => Config.current = previousConfig);

      Config.current = Config({
        'cors': {
          'allowed_origins': ['http://c'],
        },
      });
      final res = await Cors().handle(
        Request.create(headers: {'origin': 'http://c'}),
        (r) => Response.text('ok'),
      );
      expect(res.headers['access-control-allow-origin'], 'http://c');
    });
  });

  group('ThrottleRequests', () {
    test(
      'limits per ip and route, then 429 with retry-after, then resets',
      () async {
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final throttle = ThrottleRequests(
          maxAttempts: 2,
          decayMinutes: 1,
          now: () => now,
        );
        final route = RouteDefinition(['GET'], '/x', (Request r) => 1);
        Future<Response> hit() async {
          try {
            return await throttle.handle(
              Request.create(path: '/x')..route = route,
              (r) => Response.text('ok'),
            );
          } on HttpException catch (e) {
            return Response.text(
              e.message,
              status: e.statusCode,
            ).withHeaders(e.headers);
          }
        }

        final first = await hit();
        expect(first.headers['x-ratelimit-limit'], '2');
        expect(first.headers['x-ratelimit-remaining'], '1');
        await hit();
        final third = await hit();
        expect(third.statusCode, 429);
        expect(third.headers['retry-after'], '60');
        now = now.add(const Duration(seconds: 61));
        expect((await hit()).statusCode, 200);
      },
    );

    test('factory parses "60,1" style params', () {
      final m = ThrottleRequests.factory(['5', '2']);
      expect(m.maxAttempts, 5);
      expect(m.decayMinutes, 2);
    });
  });
}
