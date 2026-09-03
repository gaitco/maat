import 'dart:convert';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  test('posts the signed Pusher event to the configured endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Uri uri;
    late HttpHeaders headers;
    late String body;
    server.listen((request) async {
      uri = request.uri;
      headers = request.headers;
      body = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..write('accepted');
      await request.response.close();
    });

    final broadcaster = PusherBroadcaster(
      appId: 'app-id',
      key: 'app-key',
      secret: 'app-secret',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      scheme: 'http',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );

    await broadcaster.broadcast(
      ['tasks'],
      'TaskChanged',
      {'id': 1},
      exceptSocketId: '123.456',
    );

    expect(
      body,
      r'{"name":"TaskChanged","channels":["tasks"],"data":"{\"id\":1}","socket_id":"123.456"}',
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(uri.path, '/apps/app-id/events');
    expect(headers.contentType?.mimeType, ContentType.json.mimeType);
    expect(headers.contentLength, utf8.encode(body).length);
    expect(decoded['name'], 'TaskChanged');
    expect(decoded['channels'], ['tasks']);
    expect(decoded['data'], jsonEncode({'id': 1}));
    expect(decoded['socket_id'], '123.456');
    expect(uri.queryParameters['auth_key'], 'app-key');
    expect(uri.queryParameters['auth_timestamp'], '1725321600');
    expect(uri.queryParameters['auth_version'], '1.0');
    expect(uri.queryParameters['body_md5'], '06b7f2df199e63926dc8b701fa834288');
    expect(
      uri.queryParameters['auth_signature'],
      'bfa38b347b321c00ed4b154be1b40bd9fc6dafeea895d871a9ae0e4fdea96222',
    );
  });

  test('reports an HTTP failure without exposing the secret', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('app-secret');
      await request.response.close();
    });
    final broadcaster = PusherBroadcaster(
      appId: 'app-id',
      key: 'app-key',
      secret: 'app-secret',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      scheme: 'http',
      clock: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

    await expectLater(
      broadcaster.broadcast(['tasks'], 'TaskChanged', {'id': 1}),
      throwsA(
        isA<StateError>()
            .having((error) => '$error', 'message', contains('401'))
            .having(
              (error) => '$error',
              'message',
              isNot(contains('app-secret')),
            ),
      ),
    );
  });
}
