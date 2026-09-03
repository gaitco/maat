import 'package:maat/maat.dart';
import 'package:test/test.dart';

class OrderShipped {
  OrderShipped(this.orderId);
  final int orderId;
}

class PaymentFailed {}

abstract class Auditable {}

class UserDeleted implements Auditable {}

class SendShipmentNotification extends Listener<OrderShipped> {
  final List<int> handled = [];

  @override
  Future<void> handle(OrderShipped event) async {
    handled.add(event.orderId);
  }
}

class OrderSubscriber extends EventSubscriber {
  final List<String> log = [];

  @override
  void subscribe(Dispatcher events) {
    events.listen<OrderShipped>((event) => log.add('shipped ${event.orderId}'));
    events.listen<PaymentFailed>((_) => log.add('failed'));
  }
}

void main() {
  late Dispatcher events;

  setUp(() => events = Dispatcher());

  test('dispatches matching listeners in registration order', () async {
    final calls = <String>[];
    events.listen<OrderShipped>((event) => calls.add('a${event.orderId}'));
    events.listen<OrderShipped>(
      (event) async => calls.add('b${event.orderId}'),
    );
    events.listen<PaymentFailed>((_) => calls.add('never'));

    expect(await events.dispatch(OrderShipped(7)), [null, null]);
    expect(calls, ['a7', 'b7']);
  });

  test('returns responses and stops propagation on false', () async {
    var reached = false;
    events.listen<OrderShipped>((event) => event.orderId * 2);
    events.listen<OrderShipped>((_) => false);
    events.listen<OrderShipped>((_) => reached = true);

    expect(await events.dispatch(OrderShipped(2)), [4]);
    expect(reached, isFalse);
  });

  test('until returns the first non-null response', () async {
    var reached = false;
    events.listen<OrderShipped>((_) => null);
    events.listen<OrderShipped>((_) => 'first');
    events.listen<OrderShipped>((_) => reached = true);

    expect(await events.until(OrderShipped(1)), 'first');
    expect(reached, isFalse);
    expect(await events.until(PaymentFailed()), isNull);
  });

  test('class listeners are callable', () async {
    final listener = SendShipmentNotification();
    events.listen<OrderShipped>(listener.call);

    await events.dispatch(OrderShipped(9));

    expect(listener.handled, [9]);
  });

  test('Object and interface listeners catch subtypes', () async {
    final seen = <String>[];
    events.listen<Object>((event) => seen.add('any:${event.runtimeType}'));
    events.listen<Auditable>((event) => seen.add('audit:${event.runtimeType}'));

    await events.dispatch(UserDeleted());
    await events.dispatch(PaymentFailed());

    expect(seen, ['any:UserDeleted', 'audit:UserDeleted', 'any:PaymentFailed']);
  });

  test(
    'hasListeners includes Object listeners and forget removes exact type',
    () {
      expect(events.hasListeners<OrderShipped>(), isFalse);
      events.listen<OrderShipped>((_) => null);
      expect(events.hasListeners<OrderShipped>(), isTrue);
      expect(events.hasListeners<PaymentFailed>(), isFalse);

      events.forget<OrderShipped>();
      expect(events.hasListeners<OrderShipped>(), isFalse);

      events.listen<Object>((_) => null);
      expect(events.hasListeners<PaymentFailed>(), isTrue);
    },
  );

  test('subscriber registers all its listeners', () async {
    final subscriber = OrderSubscriber();
    events.subscribe(subscriber);

    await events.dispatch(OrderShipped(3));
    await events.dispatch(PaymentFailed());

    expect(subscriber.log, ['shipped 3', 'failed']);
  });

  test('listeners added during dispatch start on the next dispatch', () async {
    var lateCalls = 0;
    events.listen<OrderShipped>(
      (_) => events.listen<OrderShipped>((_) => lateCalls++),
    );

    await events.dispatch(OrderShipped(1));
    expect(lateCalls, 0);

    await events.dispatch(OrderShipped(1));
    expect(lateCalls, 1);
  });
}
