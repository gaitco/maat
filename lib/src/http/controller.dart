import 'dart:async';

import 'exceptions.dart';
import 'request.dart';

/// Base class for controllers. Like Laravel 11's, it is empty apart from
/// [middleware], the port of `HasMiddleware::middleware()`.
///
/// A controller whose class defines `call(Request request)` is a
/// single-action controller and may be passed as a route handler directly:
/// `Route.get('/profile', ShowProfile())`.
abstract class Controller {
  /// Middleware this controller wants on its actions. Entries are anything
  /// a route accepts (an alias, a [Middleware] instance) or a
  /// [ControllerMiddleware] limited to some actions.
  ///
  /// Applied wherever the router can see the controller: `Route.resource`,
  /// a single-action controller used as a handler, and routes registered
  /// inside `Route.controller(this).group(...)`. A bare method tear-off
  /// (`Route.get('/x', posts.index)`) carries no reference to the
  /// controller, so it gets none of this.
  List<Object> middleware() => const [];
}

/// Middleware scoped to some of a controller's actions, Laravel's
/// `new Middleware('auth', only: [...])`. Actions are named by tear-off:
///
/// ```dart
/// ControllerMiddleware('auth', except: [index, show])
/// ```
class ControllerMiddleware {
  ControllerMiddleware(
    this.middleware, {
    this.only = const [],
    this.except = const [],
  });

  final Object middleware;
  final List<Function> only;
  final List<Function> except;

  bool appliesTo(Function action) =>
      (only.isEmpty || only.contains(action)) && !except.contains(action);
}

/// The middleware [controller] declares for [action].
List<Object> controllerMiddlewareFor(Controller controller, Function action) =>
    [
      for (final entry in controller.middleware())
        if (entry is ControllerMiddleware) ...[
          if (entry.appliesTo(action)) entry.middleware,
        ] else
          entry,
    ];

/// A controller usable with `Route.resource`. Override the actions you expose;
/// the rest respond 404.
abstract class ResourceController extends Controller {
  FutureOr<Object?> index(Request request) => throw NotFoundHttpException();
  FutureOr<Object?> store(Request request) => throw NotFoundHttpException();
  FutureOr<Object?> show(Request request, String id) =>
      throw NotFoundHttpException();
  FutureOr<Object?> update(Request request, String id) =>
      throw NotFoundHttpException();
  FutureOr<Object?> destroy(Request request, String id) =>
      throw NotFoundHttpException();
}
