import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

class _User implements Authenticatable {
  const _User(this.id);

  final int id;

  @override
  Object get authIdentifier => id;

  @override
  String get authPassword => '';
}

class _HeaderGuard implements Guard {
  @override
  Future<Authenticatable?> user(Request request) async =>
      request.header('x-deny') == null ? const _User(7) : null;
}

void main() {
  late Directory directory;

  setUp(() {
    Application.reset();
    directory = Directory.systemTemp.createTempSync('channel_auth');
    Auth.extend('test', _HeaderGuard.new);
  });

  tearDown(() {
    Application.reset();
    directory.deleteSync(recursive: true);
  });

  Future<Application> build() =>
      Application.configure(basePath: directory.path, environment: {})
          .withConfig({
            'auth': {
              'defaults': {'guard': 'test'},
            },
            'broadcasting': {
              'default': 'pusher',
              'connections': {
                'pusher': {
                  'driver': 'pusher',
                  'app_id': 'app-id',
                  'key': 'app-key',
                  'secret': 'app-secret',
                  'host': '127.0.0.1',
                  'port': 6001,
                  'scheme': 'http',
                },
              },
            },
          })
          .withProviders([BroadcastServiceProvider.new])
          .create();

  test(
    'matches escaped literals and captures one non-dot, non-slash segment',
    () async {
      final registry = ChannelAuthorizationRegistry();
      Map<String, String>? captured;
      registry.channel('orders.v1+.{orderId}', (user, params) {
        captured = params;
        return true;
      });

      expect(
        await registry.authorize('private-orders.v1+.42', const _User(7)),
        isTrue,
      );
      expect(captured, {'orderId': '42'});
      expect(
        await registry.authorize('private-ordersXv11.42', const _User(7)),
        isNull,
      );
      expect(
        await registry.authorize('private-orders.v1+.4.2', const _User(7)),
        isNull,
      );
      expect(
        await registry.authorize('private-orders.v1+.42/extra', const _User(7)),
        isNull,
      );
    },
  );

  test(
    'strips exactly one channel prefix and preserves registration order',
    () async {
      final registry = ChannelAuthorizationRegistry();
      final calls = <String>[];
      registry.channel('private-orders.{id}', (user, params) {
        calls.add('first');
        return true;
      });
      registry.channel('private-orders.{id}', (user, params) {
        calls.add('second');
        return true;
      });

      expect(
        await registry.authorize('private-private-orders.42', const _User(7)),
        isTrue,
      );
      expect(calls, ['first']);
      expect(registry.patterns, ['private-orders.{id}', 'private-orders.{id}']);
    },
  );

  test('authorizes a private channel through the configured guard', () async {
    final application = await build();
    Broadcast.channel('orders.{orderId}', (user, params) async {
      return user.authIdentifier == 7 && params['orderId'] == '42';
    });

    final response = await TestClient(application).postJson(
      '/broadcasting/auth',
      {'socket_id': '123.456', 'channel_name': 'private-orders.42'},
    );

    response
      ..assertOk()
      ..assertJsonPath(
        'auth',
        'app-key:603b7287bf28824dab0789b6a7866ffe4ea69b857e9501adf6f60682cd207eeb',
      );
  });

  test('returns the same generic 403 for every denial branch', () async {
    final application = await build();
    Broadcast.channel('orders.{id}', (user, params) => false);
    final client = TestClient(application);

    final responses = [
      await client.postJson(
        '/broadcasting/auth',
        {'socket_id': '123.456', 'channel_name': 'private-orders.42'},
        {'x-deny': 'yes'},
      ),
      await client.postJson('/broadcasting/auth', {
        'socket_id': '123.456',
        'channel_name': 'private-missing.42',
      }),
      await client.postJson('/broadcasting/auth', {
        'socket_id': '123.456',
        'channel_name': 'private-orders.42',
      }),
      await client.postJson('/broadcasting/auth', {
        'socket_id': '',
        'channel_name': 'private-orders.42',
      }),
      await client.postJson('/broadcasting/auth', {
        'socket_id': '123.456',
        'channel_name': 42,
      }),
    ];

    for (final response in responses) {
      response
        ..assertForbidden()
        ..assertJson({'message': 'Forbidden'});
    }
    expect(responses.map((response) => response.body).toSet(), hasLength(1));
  });

  test(
    'returns authorizer denial before resolving signing credentials',
    () async {
      final application = await build();
      Broadcast.channel('orders.{id}', (user, params) => false);
      application.config.set('broadcasting.connections.pusher.secret', null);

      final response = await TestClient(application).postJson(
        '/broadcasting/auth',
        {'socket_id': '123.456', 'channel_name': 'private-orders.42'},
      );

      response
        ..assertForbidden()
        ..assertJson({'message': 'Forbidden'});
    },
  );

  test('signs and returns the exact serialized presence channel data', () async {
    final application = await build();
    Broadcast.channel('chat.{roomId}', (user, params) async {
      return <String, Object?>{'name': 'Ada'};
    });

    final response = await TestClient(application).postJson(
      '/broadcasting/auth',
      {'socket_id': '123.456', 'channel_name': 'presence-chat.1'},
    );

    response
      ..assertOk()
      ..assertJsonPath(
        'channel_data',
        r'{"user_id":"7","user_info":{"name":"Ada"}}',
      )
      ..assertJsonPath(
        'auth',
        'app-key:79ba2d807d9926772539eef9cfe77affc503a832add932c5f53d2d7c4f3311be',
      );
  });
}
