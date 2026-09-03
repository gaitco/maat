import 'dart:convert';
import 'dart:io';

import 'broadcaster.dart';
import 'pusher_signer.dart';

class PusherBroadcaster implements Broadcaster {
  PusherBroadcaster({
    required this.appId,
    required this.key,
    required String secret,
    required this.host,
    required this.port,
    required this.scheme,
    DateTime Function()? clock,
    HttpClient Function()? clientFactory,
  }) : _clock = clock ?? DateTime.now,
       _clientFactory = clientFactory ?? HttpClient.new,
       _signer = PusherSigner(secret);

  final String appId;
  final String key;
  final String host;
  final int port;
  final String scheme;
  final DateTime Function() _clock;
  final HttpClient Function() _clientFactory;
  final PusherSigner _signer;

  @override
  Future<void> broadcast(
    List<String> channels,
    String event,
    Map<String, Object?> payload, {
    String? exceptSocketId,
  }) async {
    final body = jsonEncode({
      'name': event,
      'channels': channels,
      'data': jsonEncode(payload),
      'socket_id': ?exceptSocketId,
    });
    final path = '/${Uri(pathSegments: ['apps', appId, 'events']).path}';
    final query = _signer.signHttp(
      method: 'POST',
      path: path,
      body: body,
      key: key,
      timestamp:
          _clock().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
    );
    final uri = Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: path,
      queryParameters: query,
    );
    final client = _clientFactory();

    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      if (status < 200 || status >= 300) {
        throw StateError('Pusher broadcast failed with HTTP $status.');
      }
    } finally {
      client.close();
    }
  }
}
