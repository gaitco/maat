import '../testing/test_response.dart' show TestClientAssertionError;
import 'broadcaster.dart';

class SentBroadcast {
  SentBroadcast(
    List<String> channels,
    this.event,
    Map<String, Object?> payload, {
    this.exceptSocketId,
  }) : channels = List.unmodifiable(channels),
       payload = Map.unmodifiable(payload);

  final List<String> channels;
  final String event;
  final Map<String, Object?> payload;
  final String? exceptSocketId;
}

class BroadcastFake implements Broadcaster {
  final List<SentBroadcast> _sent = [];

  List<SentBroadcast> get sent => List.unmodifiable(_sent);

  @override
  Future<void> broadcast(
    List<String> channels,
    String event,
    Map<String, Object?> payload, {
    String? exceptSocketId,
  }) async {
    _sent.add(
      SentBroadcast(channels, event, payload, exceptSocketId: exceptSocketId),
    );
  }

  List<SentBroadcast> broadcasted(
    String event, [
    bool Function(SentBroadcast sent)? where,
  ]) => _sent
      .where((sent) => sent.event == event)
      .where(where ?? (_) => true)
      .toList();

  void assertBroadcasted(
    String event, [
    bool Function(SentBroadcast sent)? where,
  ]) {
    if (broadcasted(event, where).isEmpty) {
      throw TestClientAssertionError(
        'The expected [$event] broadcast was not sent.',
      );
    }
  }

  void assertNotBroadcasted(
    String event, [
    bool Function(SentBroadcast sent)? where,
  ]) {
    if (broadcasted(event, where).isNotEmpty) {
      throw TestClientAssertionError(
        'The unexpected [$event] broadcast was sent.',
      );
    }
  }

  void assertBroadcastedTimes(String event, int times) {
    final count = broadcasted(event).length;
    if (count != times) {
      throw TestClientAssertionError(
        'The expected [$event] broadcast was sent $count times instead of $times times.',
      );
    }
  }

  void assertNothingBroadcasted() {
    if (_sent.isNotEmpty) {
      throw TestClientAssertionError(
        '${_sent.length} unexpected broadcasts were sent.',
      );
    }
  }
}
