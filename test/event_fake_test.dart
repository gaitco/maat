import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

class OrderShipped {
  OrderShipped(this.orderId);
  final int orderId;
}

class PaymentFailed {}

void main() {
  late Directory directory;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('event-fake');
    await Application.configure(
      basePath: directory.path,
      environment: {},
    ).create();
  });
  tearDown(() {
    Application.reset();
    directory.deleteSync(recursive: true);
  });

  final assertionFailure = throwsA(isA<TestClientAssertionError>());

  test('records dispatch and until without firing listeners', () async {
    var fired = false;
    Event.listen<OrderShipped>((_) => fired = true);
    final fake = Event.fake();

    expect(identical(app<Dispatcher>(), fake), isTrue);
    await event(OrderShipped(1));
    await Event.until(OrderShipped(2));

    expect(fired, isFalse);
    expect(fake.dispatched<OrderShipped>().map((event) => event.orderId), [
      1,
      2,
    ]);
    fake.assertDispatched<OrderShipped>();
    fake.assertDispatched<OrderShipped>((event) => event.orderId == 2);
    fake.assertDispatchedTimes<OrderShipped>(2);
    fake.assertNotDispatched<PaymentFailed>();
    fake.assertNotDispatched<OrderShipped>((event) => event.orderId == 3);
  });

  test('failed assertions identify missing or unexpected events', () async {
    final fake = Event.fake();

    expect(() => fake.assertDispatched<OrderShipped>(), assertionFailure);
    fake.assertNothingDispatched();

    await event(OrderShipped(1));

    expect(() => fake.assertNothingDispatched(), assertionFailure);
    expect(() => fake.assertDispatchedTimes<OrderShipped>(2), assertionFailure);
    expect(() => fake.assertNotDispatched<OrderShipped>(), assertionFailure);
    expect(
      () => fake.assertDispatched<PaymentFailed>(),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            '[PaymentFailed] event was not dispatched',
          ),
        ),
      ),
    );
  });

  test('only fakes selected event types', () async {
    final fired = <String>[];
    Event.listen<OrderShipped>((_) => fired.add('shipped'));
    Event.listen<PaymentFailed>((_) => fired.add('failed'));
    final fake = Event.fake(only: [OrderShipped]);

    await event(OrderShipped(1));
    await event(PaymentFailed());

    expect(fired, ['failed']);
    fake.assertDispatched<OrderShipped>();
    fake.assertNotDispatched<PaymentFailed>();
  });

  test('registrations after faking reach the real dispatcher', () async {
    final fake = Event.fake(only: [PaymentFailed]);
    final ids = <int>[];
    Event.listen<OrderShipped>((event) => ids.add(event.orderId));

    expect(Event.hasListeners<OrderShipped>(), isTrue);
    await event(OrderShipped(4));

    expect(ids, [4]);
    fake.assertNothingDispatched();
  });
}
