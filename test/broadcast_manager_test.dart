import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Shipped implements ShouldBroadcast, BroadcastsWith {
  @override
  List<Channel> broadcastOn() => const [Channel('orders')];

  @override
  Map<String, Object?> broadcastWith() => const {'id': 7};
}

class NeverBroadcast implements ShouldBroadcast, BroadcastsWhen {
  @override
  List<Channel> broadcastOn() => const [Channel('orders')];

  @override
  bool broadcastWhen() => false;
}

void main() {
  test('factory connections are created once on first resolution', () {
    var creations = 0;
    final driver = BroadcastFake();
    final manager = BroadcastManager.factories({
      'fake': () {
        creations++;
        return driver;
      },
    }, defaultConnection: 'fake');

    expect(creations, 0);
    final first = manager.connection();
    final second = manager.connection('fake');
    expect(identical(first, second), isTrue);
    expect(creations, 1);
  });

  test('manager derives event name payload channels and exclusion', () async {
    final fake = BroadcastFake();
    final manager = BroadcastManager({'fake': fake}, defaultConnection: 'fake');
    final request = Request.create(
      method: 'POST',
      path: '/',
      form: {'_socket_id': '123.456'},
    );

    await manager.pending(Shipped()).toOthers(request).send();

    final sent = fake.sent.single;
    expect(sent.channels, ['orders']);
    expect(sent.event, 'Shipped');
    expect(sent.payload, {'id': 7});
    expect(sent.exceptSocketId, '123.456');
  });

  test('BroadcastsWhen false skips the driver', () async {
    final fake = BroadcastFake();
    final manager = BroadcastManager({'fake': fake}, defaultConnection: 'fake');

    await manager.send(NeverBroadcast());

    expect(fake.sent, isEmpty);
  });
}
