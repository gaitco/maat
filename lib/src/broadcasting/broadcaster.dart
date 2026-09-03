import '../support/log.dart';

abstract interface class Broadcaster {
  Future<void> broadcast(
    List<String> channels,
    String event,
    Map<String, Object?> payload, {
    String? exceptSocketId,
  });
}

class LogBroadcaster implements Broadcaster {
  @override
  Future<void> broadcast(
    List<String> channels,
    String event,
    Map<String, Object?> payload, {
    String? exceptSocketId,
  }) async {
    Log.info('Broadcasting $event on ${channels.join(', ')}');
  }
}

class NullBroadcaster implements Broadcaster {
  @override
  Future<void> broadcast(
    List<String> channels,
    String event,
    Map<String, Object?> payload, {
    String? exceptSocketId,
  }) async {}
}
