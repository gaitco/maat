import '../http/request.dart';
import 'broadcaster.dart';
import 'channel.dart';
import 'contracts.dart';

class BroadcastManager {
  BroadcastManager(
    Map<String, Broadcaster> connections, {
    required this.defaultConnection,
  }) : _connections = Map.of(connections),
       _factories = const {};

  BroadcastManager.factories(
    Map<String, Broadcaster Function()> factories, {
    required this.defaultConnection,
  }) : _connections = {},
       _factories = Map.of(factories);

  final Map<String, Broadcaster> _connections;
  final Map<String, Broadcaster Function()> _factories;
  final String defaultConnection;

  Broadcaster connection([String? name]) {
    final connectionName = name ?? defaultConnection;
    final existing = _connections[connectionName];
    if (existing != null) return existing;
    final factory = _factories[connectionName];
    if (factory == null) {
      throw StateError(
        'Broadcast connection [$connectionName] is not configured.',
      );
    }
    return _connections[connectionName] = factory();
  }

  PendingBroadcast pending(Object event) => PendingBroadcast(this, event);

  PendingBroadcast on(String name) =>
      pending(_PendingEvent([Channel(name)], '', const {}));

  Future<void> send(Object event, {String? exceptSocketId}) async {
    if (event is BroadcastsWhen && !event.broadcastWhen()) return;
    if (event is! ShouldBroadcast) return;
    final channels = event.broadcastOn().map((c) => c.prefixedName).toList();
    final name = event is BroadcastsAs
        ? (event as BroadcastsAs).broadcastAs()
        : event.runtimeType.toString();
    final payload = event is BroadcastsWith
        ? (event as BroadcastsWith).broadcastWith()
        : const <String, Object?>{};
    await connection().broadcast(
      channels,
      name,
      payload,
      exceptSocketId: exceptSocketId,
    );
  }
}

class PendingBroadcast {
  PendingBroadcast(this._manager, this._event);

  final BroadcastManager _manager;
  final Object _event;
  String? _exceptSocketId;

  PendingBroadcast toOthers(Request request) {
    final socketId = request.header('x-socket-id');
    final input = request.input('_socket_id');
    _exceptSocketId =
        socketId ?? (input is String && input.isNotEmpty ? input : null);
    return this;
  }

  PendingBroadcast as(String name) {
    if (_event case final _PendingEvent event) event.name = name;
    return this;
  }

  PendingBroadcast with_(Map<String, Object?> payload) {
    if (_event case final _PendingEvent event) event.payload = payload;
    return this;
  }

  Future<void> send() => _manager.send(_event, exceptSocketId: _exceptSocketId);
}

class _PendingEvent implements ShouldBroadcast, BroadcastsAs, BroadcastsWith {
  _PendingEvent(this.channels, this.name, this.payload);

  final List<Channel> channels;
  String name;
  Map<String, Object?> payload;

  @override
  List<Channel> broadcastOn() => channels;

  @override
  String broadcastAs() => name;

  @override
  Map<String, Object?> broadcastWith() => payload;
}
