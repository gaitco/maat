import 'dart:async';

import '../testing/test_response.dart' show TestClientAssertionError;
import 'dispatcher.dart';

class EventFake extends Dispatcher {
  EventFake(this._dispatcher, {this.only = const []});

  final Dispatcher _dispatcher;
  final List<Type> only;
  final List<Object> _dispatched = [];

  @override
  FutureOr<void> Function(Object event)? get afterDispatch =>
      _dispatcher.afterDispatch;

  @override
  set afterDispatch(FutureOr<void> Function(Object event)? callback) {
    _dispatcher.afterDispatch = callback;
  }

  bool _fakes(Object event) => only.isEmpty || only.contains(event.runtimeType);

  @override
  Future<List<Object?>> dispatch(Object event) {
    if (!_fakes(event)) return _dispatcher.dispatch(event);
    _dispatched.add(event);
    return Future.value(const []);
  }

  @override
  Future<Object?> until(Object event) {
    if (!_fakes(event)) return _dispatcher.until(event);
    _dispatched.add(event);
    return Future.value();
  }

  @override
  void listen<E extends Object>(ListenerCallback<E> listener) =>
      _dispatcher.listen<E>(listener);

  @override
  bool hasListeners<E extends Object>() => _dispatcher.hasListeners<E>();

  @override
  void forget<E extends Object>() => _dispatcher.forget<E>();

  @override
  void subscribe(EventSubscriber subscriber) =>
      _dispatcher.subscribe(subscriber);

  List<Object> get dispatchedEvents => List.unmodifiable(_dispatched);

  List<E> dispatched<E extends Object>([bool Function(E event)? where]) =>
      _dispatched.whereType<E>().where(where ?? (_) => true).toList();

  void assertDispatched<E extends Object>([bool Function(E event)? where]) {
    if (dispatched<E>(where).isEmpty) {
      throw TestClientAssertionError(
        where == null
            ? 'The expected [$E] event was not dispatched.'
            : 'The expected [$E] event was not dispatched with a matching payload.',
      );
    }
  }

  void assertDispatchedTimes<E extends Object>(int times) {
    final count = dispatched<E>().length;
    if (count != times) {
      throw TestClientAssertionError(
        'The expected [$E] event was dispatched $count times instead of $times times.',
      );
    }
  }

  void assertNotDispatched<E extends Object>([bool Function(E event)? where]) {
    if (dispatched<E>(where).isNotEmpty) {
      throw TestClientAssertionError(
        'The unexpected [$E] event was dispatched.',
      );
    }
  }

  void assertNothingDispatched() {
    if (_dispatched.isNotEmpty) {
      final names = _dispatched.map((event) => event.runtimeType).join(', ');
      throw TestClientAssertionError(
        '${_dispatched.length} unexpected events were dispatched: $names.',
      );
    }
  }
}
