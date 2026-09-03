import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

class OrderShipped with Dispatchable {
  OrderShipped(this.orderId);
  final int orderId;
}

class BootListeners extends ServiceProvider {
  BootListeners(super.app, this.log);

  final List<int> log;

  @override
  void boot() {
    Event.listen<OrderShipped>((event) => log.add(event.orderId));
  }
}

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('events'));
  tearDown(() {
    Application.reset();
    directory.deleteSync(recursive: true);
  });

  Future<Application> build([
    List<ServiceProvider Function(Application)> providers = const [],
  ]) => Application.configure(
    basePath: directory.path,
    environment: {},
  ).withProviders(providers).create();

  test('application binds one Dispatcher instance', () async {
    final application = await build();

    expect(
      identical(application.make<Dispatcher>(), app<Dispatcher>()),
      isTrue,
    );
    expect(identical(Event.dispatcher, app<Dispatcher>()), isTrue);
  });

  test('facade, helper, and mixin share the dispatcher', () async {
    await build();
    final ids = <int>[];
    Event.listen<OrderShipped>((event) => ids.add(event.orderId));
    Event.listen<OrderShipped>((event) => event.orderId == 4 ? true : null);

    await Event.dispatch(OrderShipped(1));
    await event(OrderShipped(2));
    await OrderShipped(3).dispatch();

    expect(ids, [1, 2, 3]);
    expect(await Event.until(OrderShipped(4)), isTrue);
    expect(Event.hasListeners<OrderShipped>(), isTrue);
    Event.forget<OrderShipped>();
    expect(Event.hasListeners<OrderShipped>(), isFalse);
  });

  test('provider boot may register listeners', () async {
    final ids = <int>[];
    await build([(application) => BootListeners(application, ids)]);

    await event(OrderShipped(5));

    expect(ids, [5]);
  });

  test('facade throws before an application exists', () {
    expect(() => Event.dispatch(OrderShipped(1)), throwsStateError);
  });
}
