import 'dart:convert';

import '../auth/auth.dart';
import '../events/dispatcher.dart';
import '../foundation/service_provider.dart';
import '../http/request.dart';
import '../http/response.dart';
import '../routing/route.dart';
import 'broadcast_manager.dart';
import 'broadcaster.dart';
import 'channel_authorization.dart';
import 'contracts.dart';
import 'pusher_broadcaster.dart';
import 'pusher_signer.dart';

class BroadcastServiceProvider extends ServiceProvider {
  BroadcastServiceProvider(super.app);

  @override
  void register() {
    app.singleton<ChannelAuthorizationRegistry>(
      (_) => ChannelAuthorizationRegistry(),
    );
    app.singleton<BroadcastManager>((_) => _manager());
  }

  @override
  void boot() {
    Route.post('/broadcasting/auth', _authorize);
    app.make<Dispatcher>().afterDispatch = (event) async {
      if (event is ShouldBroadcast) {
        await app.make<BroadcastManager>().send(event);
      }
    };
  }

  BroadcastManager _manager() {
    final defaultConnection = _requiredString('broadcasting.default');
    final configured = app.config.get('broadcasting.connections');
    if (configured is! Map) {
      throw StateError('Missing configuration [broadcasting.connections].');
    }
    final connections = <String, Broadcaster Function()>{};
    for (final entry in configured.entries) {
      final name = entry.key.toString();
      final path = 'broadcasting.connections.$name';
      final settings = entry.value;
      final driver = settings is Map ? settings['driver'] : null;
      if (driver is! String || driver.isEmpty) {
        throw StateError('Missing configuration [$path.driver].');
      }
      connections[name] = switch (driver) {
        'log' => LogBroadcaster.new,
        'null' => NullBroadcaster.new,
        'pusher' => () => _pusher(path),
        _ => throw StateError('Unsupported configuration [$path.driver].'),
      };
    }
    if (!connections.containsKey(defaultConnection)) {
      throw StateError('Missing configuration [broadcasting.connections].');
    }
    return BroadcastManager.factories(
      connections,
      defaultConnection: defaultConnection,
    );
  }

  PusherBroadcaster _pusher(String path) => PusherBroadcaster(
    appId: _requiredString('$path.app_id'),
    key: _requiredString('$path.key'),
    secret: _requiredString('$path.secret'),
    host: _optionalString('$path.host', '127.0.0.1'),
    port: _optionalInt('$path.port', 6001),
    scheme: _optionalString('$path.scheme', 'http'),
  );

  Future<Response> _authorize(Request request) async {
    final socketId = request.input('socket_id');
    final channelName = request.input('channel_name');
    if (socketId is! String ||
        socketId.trim().isEmpty ||
        channelName is! String ||
        channelName.trim().isEmpty ||
        (!channelName.startsWith('private-') &&
            !channelName.startsWith('presence-'))) {
      return _forbidden();
    }

    final guardName =
        (app.config.get('auth.defaults.guard') as String?) ?? 'cartouche';
    final authenticated = await Auth.guard(guardName).user(request);
    if (authenticated == null) return _forbidden();
    request.attributes[authUserAttribute] = authenticated;
    request.attributes[authResolvedAttribute] = true;
    final user = request.user();
    if (user == null) return _forbidden();

    final result = await app.make<ChannelAuthorizationRegistry>().authorize(
      channelName,
      user,
    );
    String? channelData;
    if (channelName.startsWith('presence-')) {
      if (result is! Map<String, Object?>) return _forbidden();
      channelData = jsonEncode({
        'user_id': user.authIdentifier.toString(),
        'user_info': result,
      });
    } else if (result != true) {
      return _forbidden();
    }

    final pusherPath = 'broadcasting.connections.pusher';
    final key = _requiredString('$pusherPath.key');
    final signer = PusherSigner(_requiredString('$pusherPath.secret'));
    final signature = signer.subscriptionSignature(
      socketId,
      channelName,
      channelData: channelData,
    );
    return Response.json({
      'auth': '$key:$signature',
      'channel_data': ?channelData,
    });
  }

  Response _forbidden() =>
      Response.json(const {'message': 'Forbidden'}, status: 403);

  String _requiredString(String key) {
    final value = app.config.get(key);
    if (value is String && value.isNotEmpty) return value;
    throw StateError('Missing configuration [$key].');
  }

  String _optionalString(String key, String fallback) {
    final value = app.config.get(key);
    return value is String && value.isNotEmpty ? value : fallback;
  }

  int _optionalInt(String key, int fallback) {
    final value = app.config.get(key);
    return value is int ? value : fallback;
  }
}
