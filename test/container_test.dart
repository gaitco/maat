import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Counter {
  static int created = 0;
  Counter() {
    created++;
  }
}

abstract class Clock {
  int now();
}

class FixedClock implements Clock {
  @override
  int now() => 42;
}

void main() {
  setUp(() => Counter.created = 0);

  test('bind returns a new instance on every make', () {
    final c = Container()..bind<Counter>((_) => Counter());
    c.make<Counter>();
    c.make<Counter>();
    expect(Counter.created, 2);
  });

  test('singleton is created lazily once', () {
    final c = Container()..singleton<Counter>((_) => Counter());
    expect(Counter.created, 0);
    final a = c.make<Counter>();
    final b = c.make<Counter>();
    expect(identical(a, b), isTrue);
    expect(Counter.created, 1);
  });

  test('instance registers an existing object', () {
    final clock = FixedClock();
    final c = Container()..instance<Clock>(clock);
    expect(identical(c.make<Clock>(), clock), isTrue);
  });

  test('abstract to concrete binding', () {
    final c = Container()..bind<Clock>((_) => FixedClock());
    expect(c.make<Clock>().now(), 42);
  });

  test('factory receives the container to resolve dependencies', () {
    final c = Container()
      ..singleton<Clock>((_) => FixedClock())
      ..bind<int>((c) => c.make<Clock>().now());
    expect(c.make<int>(), 42);
  });

  test('make of unbound type throws BindingResolutionException', () {
    final c = Container();
    expect(
      () => c.make<Clock>(),
      throwsA(
        isA<BindingResolutionException>().having(
          (e) => e.toString(),
          'message',
          contains('Clock'),
        ),
      ),
    );
  });

  test('has reports bindings and instances', () {
    final c = Container()..bind<Clock>((_) => FixedClock());
    expect(c.has<Clock>(), isTrue);
    expect(c.has<Counter>(), isFalse);
  });

  test('instance after singleton replaces the resolved object', () {
    final c = Container()..singleton<Clock>((_) => FixedClock());
    final first = c.make<Clock>();
    final replacement = FixedClock();
    c.instance<Clock>(replacement);
    expect(identical(c.make<Clock>(), replacement), isTrue);
    expect(identical(c.make<Clock>(), first), isFalse);
  });
}
