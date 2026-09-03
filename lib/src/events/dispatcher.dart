import 'dart:async';

typedef ListenerCallback<E extends Object> =
    FutureOr<Object?> Function(E event);

abstract class Listener<E extends Object> {
  FutureOr<Object?> handle(E event);

  FutureOr<Object?> call(E event) => handle(event);
}

abstract class EventSubscriber {
  void subscribe(Dispatcher events);
}

class _Registration {
  _Registration(this.type, this.matches, this.invoke);

  final Type type;
  final bool Function(Object event) matches;
  final FutureOr<Object?> Function(Object event) invoke;
}

class Dispatcher {
  final List<_Registration> _listeners = [];

  void listen<E extends Object>(ListenerCallback<E> listener) {
    _listeners.add(
      _Registration(E, (event) => event is E, (event) => listener(event as E)),
    );
  }

  Future<List<Object?>> dispatch(Object event) async {
    final responses = <Object?>[];
    for (final registration in _matching(event)) {
      final response = await registration.invoke(event);
      if (response == false) break;
      responses.add(response);
    }
    return responses;
  }

  Future<Object?> until(Object event) async {
    for (final registration in _matching(event)) {
      final response = await registration.invoke(event);
      if (response != null) return response;
    }
    return null;
  }

  bool hasListeners<E extends Object>() => _listeners.any(
    (listener) => listener.type == E || listener.type == Object,
  );

  void forget<E extends Object>() {
    _listeners.removeWhere((listener) => listener.type == E);
  }

  void subscribe(EventSubscriber subscriber) => subscriber.subscribe(this);

  // ponytail: linear scan is simplest; index by runtime type only if profiling
  // shows event dispatch to be hot. The snapshot isolates the current dispatch.
  List<_Registration> _matching(Object event) =>
      _listeners.where((listener) => listener.matches(event)).toList();
}
