import 'dart:async';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Tag extends Middleware {
  Tag(this.tag, this.log);
  final String tag;
  final List<String> log;
  @override
  Future<Response> handle(Request request, Next next) async {
    log.add('before $tag');
    final response = await next(request);
    log.add('after $tag');
    return response.header('x-$tag', '1');
  }
}

class Block extends Middleware {
  @override
  Response handle(Request request, Next next) =>
      Response.text('blocked', status: 403);
}

class Limit extends Middleware {
  Limit(this.max);
  final int max;
  @override
  FutureOr<Response> handle(Request request, Next next) => next(request);
}

void main() {
  group('Pipeline', () {
    test('runs middleware in order around the destination', () async {
      final log = <String>[];
      final pipeline = Pipeline([Tag('a', log), Tag('b', log)]);
      final res = await pipeline.run(Request.create(), (r) {
        log.add('handler');
        return Response.text('ok');
      });
      expect(log, ['before a', 'before b', 'handler', 'after b', 'after a']);
      expect(res.headers['x-a'], '1');
      expect(res.headers['x-b'], '1');
    });

    test('middleware can short-circuit', () async {
      final log = <String>[];
      final res = await Pipeline([Tag('a', log), Block(), Tag('c', log)]).run(
        Request.create(),
        (r) {
          log.add('handler');
          return Response.text('ok');
        },
      );
      expect(res.statusCode, 403);
      expect(log, ['before a', 'after a']);
    });

    test('empty pipeline calls destination', () async {
      final res = await Pipeline(
        [],
      ).run(Request.create(), (r) => Response.text('d'));
      expect(res.body, 'd');
    });
  });

  group('MiddlewareConfig', () {
    test(
      'resolves instances, functions, aliases and parameterized aliases',
      () {
        final config = MiddlewareConfig()
          ..alias({
            'block': Block(),
            'fn': (Request r, Next n) => Response.text('fn'),
            'limit': (List<String> p) => Limit(int.parse(p[0])),
          });
        expect(config.resolve(Block()), isA<Block>());
        expect(config.resolve((Request r, Next n) => n(r)), isA<Middleware>());
        expect(config.resolve('block'), isA<Block>());
        expect(config.resolve('fn'), isA<Middleware>());
        expect((config.resolve('limit:5') as Limit).max, 5);
      },
    );

    test('unknown alias, params on plain alias, or bad type fail fast', () {
      final config = MiddlewareConfig()..alias({'block': Block()});
      expect(() => config.resolve('nope'), throwsArgumentError);
      expect(() => config.resolve('block:1'), throwsArgumentError);
      expect(() => config.resolve(42), throwsArgumentError);
    });

    test('use replaces, append and prepend edit the global stack', () {
      final a = Block();
      final b = Block();
      final config = MiddlewareConfig()
        ..use([a])
        ..append(b)
        ..prepend('x');
      expect(config.global, ['x', a, b]);
      config.use([b]);
      expect(config.global, [b]);
    });
  });

  test('withMiddleware configures the app singleton', () async {
    final dir = Directory.systemTemp.createTempSync('mw');
    addTearDown(() => dir.deleteSync(recursive: true));
    final application = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).withMiddleware((m) => m.use([Block()]).alias({'b': Block()})).create();
    final config = application.make<MiddlewareConfig>();
    expect(config.global, hasLength(1));
    expect(config.resolve('b'), isA<Block>());
  });
}
