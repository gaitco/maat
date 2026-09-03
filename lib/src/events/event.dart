import 'dart:async';

import '../foundation/application.dart';
import 'dispatcher.dart';
import 'event_fake.dart';

abstract final class Event {
  static Dispatcher get dispatcher => app<Dispatcher>();

  static void listen<E extends Object>(ListenerCallback<E> listener) =>
      dispatcher.listen<E>(listener);

  static Future<List<Object?>> dispatch(Object event) =>
      dispatcher.dispatch(event);

  static Future<Object?> until(Object event) => dispatcher.until(event);

  static bool hasListeners<E extends Object>() => dispatcher.hasListeners<E>();

  static void forget<E extends Object>() => dispatcher.forget<E>();

  static void subscribe(EventSubscriber subscriber) =>
      dispatcher.subscribe(subscriber);

  static EventFake fake({List<Type> only = const []}) {
    final fake = EventFake(dispatcher, only: only);
    Application.current.instance<Dispatcher>(fake);
    return fake;
  }
}

Future<List<Object?>> event(Object event) => Event.dispatch(event);

mixin Dispatchable {
  Future<List<Object?>> dispatch() => event(this);
}
