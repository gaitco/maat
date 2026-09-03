import 'dart:async';

import '../request.dart';
import '../response.dart';

typedef Next = FutureOr<Response> Function(Request request);
typedef MiddlewareFunction =
    FutureOr<Response> Function(Request request, Next next);
typedef MiddlewareFactory = Middleware Function(List<String> params);

/// `handle(request, next)`, exactly like Laravel.
abstract class Middleware {
  FutureOr<Response> handle(Request request, Next next);
}

class _FunctionMiddleware extends Middleware {
  _FunctionMiddleware(this._fn);
  final MiddlewareFunction _fn;
  @override
  FutureOr<Response> handle(Request request, Next next) => _fn(request, next);
}

/// Global middleware stack and string aliases, configured in `bootstrap/app.dart`.
class MiddlewareConfig {
  final List<Object> _global = [];
  final Map<String, Object> _aliases = {};
  // ponytail: memoizes string entries only ('throttle:60,1' etc) so a factory
  // alias like ThrottleRequests.factory is invoked once, not once per request.
  final Map<String, Middleware> _resolvedStrings = {};

  List<Object> get global => List.unmodifiable(_global);

  /// Replace the global stack.
  MiddlewareConfig use(List<Object> middleware) {
    _global
      ..clear()
      ..addAll(middleware);
    return this;
  }

  MiddlewareConfig append(Object middleware) {
    _global.add(middleware);
    return this;
  }

  MiddlewareConfig prepend(Object middleware) {
    _global.insert(0, middleware);
    return this;
  }

  MiddlewareConfig alias(Map<String, Object> aliases) {
    _aliases.addAll(aliases);
    _resolvedStrings.clear();
    return this;
  }

  /// Turn a middleware entry (instance, function, or `'alias:param,param'`) into a [Middleware].
  ///
  /// String entries are memoized (keyed by the full entry, so `throttle:60,1`
  /// and `throttle:10,1` are distinct) — required for stateful middleware like
  /// [ThrottleRequests] whose factory would otherwise be invoked, and its state
  /// discarded, on every single request.
  Middleware resolve(Object entry) {
    if (entry is String) {
      return _resolvedStrings.putIfAbsent(entry, () => _resolveUncached(entry));
    }
    return _resolveUncached(entry);
  }

  Middleware _resolveUncached(Object entry) {
    if (entry is Middleware) return entry;
    if (entry is MiddlewareFunction) return _FunctionMiddleware(entry);
    if (entry is String) {
      final colon = entry.indexOf(':');
      final name = colon < 0 ? entry : entry.substring(0, colon);
      final params = colon < 0
          ? const <String>[]
          : entry.substring(colon + 1).split(',');
      final target = _aliases[name];
      if (target == null) {
        throw ArgumentError('Unknown middleware alias [$name].');
      }
      if (target is MiddlewareFactory) return target(params);
      if (params.isNotEmpty) {
        throw ArgumentError(
          'Middleware alias [$name] does not accept parameters; register a factory to use [$entry].',
        );
      }
      return resolve(target);
    }
    throw ArgumentError(
      'Invalid middleware [$entry]: expected a Middleware, a function, or an alias string.',
    );
  }

  List<Middleware> resolveAll(Iterable<Object> entries) => [
    for (final e in entries) resolve(e),
  ];
}
