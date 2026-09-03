import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Shipped implements ShouldBroadcast, BroadcastsWith {
  @override
  List<Channel> broadcastOn() => const [
    Channel('orders'),
    PrivateChannel('orders.7'),
    PresenceChannel('room.2'),
  ];

  @override
  Map<String, Object?> broadcastWith() => {'id': 7};
}

void main() {
  test('channel subclasses own their protocol prefix', () {
    final channels = Shipped().broadcastOn();
    expect(channels.map((c) => c.prefixedName), [
      'orders',
      'private-orders.7',
      'presence-room.2',
    ]);
  });

  test('already-prefixed channel names keep one wire prefix', () {
    expect(
      const PrivateChannel('private-orders.7').prefixedName,
      'private-orders.7',
    );
    expect(
      const PresenceChannel('presence-room.2').prefixedName,
      'presence-room.2',
    );
  });

  test('dispatcher calls its post-dispatch hook after listeners', () async {
    final order = <String>[];
    final dispatcher = Dispatcher()
      ..listen<Shipped>((_) => order.add('listener'))
      ..afterDispatch = (_) => order.add('broadcast');
    await dispatcher.dispatch(Shipped());
    expect(order, ['listener', 'broadcast']);
  });

  test('until never invokes the broadcast hook', () async {
    var broadcasts = 0;
    final dispatcher = Dispatcher()
      ..listen<Shipped>((_) => 'first')
      ..afterDispatch = (_) => broadcasts++;
    expect(await dispatcher.until(Shipped()), 'first');
    expect(broadcasts, 0);
  });
}
