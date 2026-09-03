import 'dart:convert';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

class Boom implements Exception {}

class NoJson {}

class AddHeader extends Middleware {
  @override
  Future<Response> handle(Request request, Next next) async =>
      (await next(request)).header('x-global', '1');
}

void main() {
  late Directory dir;
  late Application application;
  late List<Object> reported;
  late StringBuffer logBuffer;

  Future<void> boot({bool debug = false, int? maxBodyBytes}) async {
    reported = [];
    application =
        await Application.configure(basePath: dir.path, environment: {})
            .withConfig({
              'app': {'debug': debug},
              if (maxBodyBytes != null)
                'http': {'max_body_bytes': maxBodyBytes},
            })
            .withMiddleware(
              (m) => m.use([AddHeader()]).alias({
                'deny': (Request r, Next n) => throw ForbiddenHttpException(),
              }),
            )
            .withExceptions((e) => e.report((err, st) => reported.add(err)))
            .create();
    Route.get('/ok', (Request r) => {'ok': true});
    Route.get('/text', (Request r) => 'hi');
    Route.get('/posts/{id}', (Request r, String id) => {'id': id});
    Route.post(
      '/posts',
      (Request r) async =>
          Response.json(await r.validate({'title': 'required'}), status: 201),
    );
    Route.get('/boom', (Request r) => throw Boom());
    Route.get('/abort', (Request r) => abort(418, 'short'));
    Route.get(
      '/short',
      (Request r) =>
          throw HttpResponseException(Response.text('custom', status: 402)),
    );
    Route.get('/denied', (Request r) => 'never').middleware(['deny']);
    Route.get('/raw-map', (Request r) => Response({'a': 1, 'b': 2}));
    Route.get('/no-json', (Request r) => Response(NoJson()));
    Route.post('/stream', (Request r) async {
      final bytes = await r.bodyStream.expand((chunk) => chunk).toList();
      return {'buffered': r.isBodyBuffered, 'body': utf8.decode(bytes)};
    }).streamRequestBody();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kernel');
    logBuffer = StringBuffer();
    Log.sink = logBuffer;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Response> send(
    String method,
    String path, {
    Object? json,
    Map<String, String> headers = const {},
  }) async {
    final kernel = application.make<HttpKernel>();
    return kernel.handle(
      Request.create(method: method, path: path, json: json, headers: headers),
    );
  }

  test('routes, params and normalization', () async {
    await boot();
    final ok = await send('GET', '/ok');
    expect(ok.statusCode, 200);
    expect(jsonDecode(ok.body as String), {'ok': true});
    expect(ok.headers['x-global'], '1');
    expect(
      (await send('GET', '/text')).headers['content-type'],
      contains('text/html'),
    );
    expect(jsonDecode((await send('GET', '/posts/9')).body as String), {
      'id': '9',
    });
    expect(
      (await send('POST', '/posts', json: {'title': 'x'})).statusCode,
      201,
    );
  });

  test('404 and 405 as JSON for api clients, HTML otherwise', () async {
    await boot();
    final missing = await send(
      'GET',
      '/nope',
      headers: {'accept': 'application/json'},
    );
    expect(missing.statusCode, 404);
    expect(jsonDecode(missing.body as String), {'message': 'Not Found'});
    final html = await send('GET', '/nope');
    expect(html.headers['content-type'], contains('text/html'));
    expect(html.body, contains('Not Found'));
    final wrong = await send('DELETE', '/ok');
    expect(wrong.statusCode, 405);
    expect(wrong.headers['allow'], 'GET, HEAD');
  });

  test('validation errors render 422 in laravel shape', () async {
    await boot();
    final res = await send(
      'POST',
      '/posts',
      json: {},
      headers: {'accept': 'application/json'},
    );
    expect(res.statusCode, 422);
    expect(jsonDecode(res.body as String), {
      'message': 'The given data was invalid.',
      'errors': {
        'title': ['The title field is required.'],
      },
    });
    expect(reported, isEmpty);
  });

  test('abort, HttpResponseException and middleware exceptions', () async {
    await boot();
    final teapot = await send(
      'GET',
      '/abort',
      headers: {'accept': 'application/json'},
    );
    expect(teapot.statusCode, 418);
    expect(jsonDecode(teapot.body as String), {'message': 'short'});
    final custom = await send('GET', '/short');
    expect(custom.statusCode, 402);
    expect(custom.body, 'custom');
    expect((await send('GET', '/denied')).statusCode, 403);
    expect(reported, isEmpty);
  });

  test('unknown errors are reported and hidden unless debug', () async {
    await boot();
    final res = await send(
      'GET',
      '/boom',
      headers: {'accept': 'application/json'},
    );
    expect(res.statusCode, 500);
    expect(jsonDecode(res.body as String), {'message': 'Server Error'});
    expect(
      res.headers['x-global'],
      '1',
      reason: 'global middleware wraps rendered errors',
    );
    expect(reported.single, isA<Boom>());
    expect(logBuffer.toString(), contains('ERROR'));

    await boot(debug: true);
    final dbg = jsonDecode(
      (await send('GET', '/boom', headers: {'accept': 'application/json'})).body
          as String,
    );
    expect(dbg['exception'], 'Boom');
    expect(dbg['trace'], isA<List>());
  });

  test('custom renderers and dontReport', () async {
    await boot();
    final handler = application.make<ExceptionHandler>()
      ..render<Boom>((e, r) => Response.json({'boom': true}, status: 503))
      ..dontReport<Boom>();
    expect(handler.shouldReport(Boom()), isFalse);
    final res = await send('GET', '/boom');
    expect(res.statusCode, 503);
    expect(reported, isEmpty);
  });

  test('handleShelf adapts shelf requests and responses', () async {
    await boot();
    final res = await application.make<HttpKernel>().handleShelf(
      shelf.Request('GET', Uri.parse('http://localhost/posts/3')),
    );
    expect(res.statusCode, 200);
    expect(await res.readAsString(), '{"id":"3"}');
  });

  test('handleShelf renders an oversized body as 413', () async {
    await boot(maxBodyBytes: 3);
    final res = await application.make<HttpKernel>().handleShelf(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/posts'),
        headers: {'accept': 'application/json'},
        body: 'four',
      ),
    );

    expect(res.statusCode, 413);
    expect(jsonDecode(await res.readAsString()), {
      'message': 'Payload Too Large',
    });
  });

  test('a streaming route consumes the body without buffering it', () async {
    await boot(maxBodyBytes: 10);
    final res = await application.make<HttpKernel>().handleShelf(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/stream'),
        headers: {'accept': 'application/json'},
        body: Stream<List<int>>.fromIterable([
          utf8.encode('one'),
          utf8.encode('two'),
        ]),
      ),
    );

    expect(res.statusCode, 200);
    expect(jsonDecode(await res.readAsString()), {
      'buffered': false,
      'body': 'onetwo',
    });
  });

  test('a streaming route still rejects a body over the byte limit', () async {
    await boot(maxBodyBytes: 3);
    final res = await application.make<HttpKernel>().handleShelf(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/stream'),
        headers: {'accept': 'application/json'},
        body: Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
    );

    expect(res.statusCode, 413);
  });

  test('serve listens on a real port', () async {
    await boot();
    final server = await application.serve(host: '127.0.0.1', port: 0);
    addTearDown(() => server.close(force: true));
    final client = HttpClient();
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/ok'),
    );
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), '{"ok":true}');
    client.close();
  });

  test('a bare Response(map) is served as JSON over a real socket, and '
      'TestClient agrees with production', () async {
    await boot();
    final server = await application.serve(host: '127.0.0.1', port: 0);
    addTearDown(() => server.close(force: true));
    final httpClient = HttpClient();
    final req = await httpClient.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/raw-map'),
    );
    final res = await req.close();
    final productionBody = await res.transform(utf8.decoder).join();
    httpClient.close();
    expect(res.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(productionBody), {'a': 1, 'b': 2});

    final testClientRes = await TestClient(application).get('/raw-map');
    expect(testClientRes.headers['content-type'], contains('application/json'));
    expect(testClientRes.body, productionBody);
  });

  test('a bare Response with an unencodable body renders a 500 instead of '
      'escaping the kernel as a raw shelf error, over a real socket and '
      'TestClient', () async {
    await boot();
    final server = await application.serve(host: '127.0.0.1', port: 0);
    addTearDown(() => server.close(force: true));
    final httpClient = HttpClient();
    final req = await httpClient.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/no-json'),
    );
    req.headers.set('accept', 'application/json');
    final res = await req.close();
    final productionBody = await res.transform(utf8.decoder).join();
    httpClient.close();
    expect(res.statusCode, 500);
    expect(res.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(productionBody), {'message': 'Server Error'});

    final testClientRes = await TestClient(
      application,
    ).get('/no-json', headers: {'accept': 'application/json'});
    expect(testClientRes.statusCode, 500);
    expect(jsonDecode(testClientRes.body), {'message': 'Server Error'});
  });

  test('a reporter that throws does not stop other reporters or prevent the '
      'response from rendering', () async {
    await boot();
    application.make<ExceptionHandler>().report(
      (error, stackTrace) => throw StateError('reporter blew up'),
    );
    final res = await send(
      'GET',
      '/boom',
      headers: {'accept': 'application/json'},
    );
    expect(res.statusCode, 500);
    expect(jsonDecode(res.body as String), {'message': 'Server Error'});
    expect(reported.single, isA<Boom>());
  });
}
