import '../foundation/application.dart';
import '../http/controller.dart';
import 'route_definition.dart';
import 'router.dart';

const _allVerbs = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'];

/// Static route registration API, mirroring Laravel's `Route` facade.
abstract final class Route {
  static Router get router => Application.current.make<Router>();

  static RouteDefinition get(String uri, Object handler) =>
      router.add(['GET', 'HEAD'], uri, handler);
  static RouteDefinition post(String uri, Object handler) =>
      router.add(['POST'], uri, handler);
  static RouteDefinition put(String uri, Object handler) =>
      router.add(['PUT'], uri, handler);
  static RouteDefinition patch(String uri, Object handler) =>
      router.add(['PATCH'], uri, handler);
  static RouteDefinition delete(String uri, Object handler) =>
      router.add(['DELETE'], uri, handler);
  static RouteDefinition options(String uri, Object handler) =>
      router.add(['OPTIONS'], uri, handler);
  static RouteDefinition any(String uri, Object handler) =>
      router.add(_allVerbs, uri, handler);
  static RouteDefinition match(
    List<String> methods,
    String uri,
    Object handler,
  ) => router.add(methods, uri, handler);

  static void group(
    void Function() body, {
    String? prefix,
    List<Object>? middleware,
    String? name,
    Controller? controller,
  }) => router.group(
    body,
    prefix: prefix,
    middleware: middleware,
    name: name,
    controller: controller,
  );

  static RouteGroupBuilder prefix(String prefix) =>
      RouteGroupBuilder().prefix(prefix);
  static RouteGroupBuilder middleware(List<Object> middleware) =>
      RouteGroupBuilder().middleware(middleware);
  static RouteGroupBuilder name(String name) => RouteGroupBuilder().name(name);

  /// Routes inside the group get [controller]'s `middleware()` applied per
  /// action: `Route.controller(orders).group(() { Route.get('/orders', orders.index); })`.
  static RouteGroupBuilder controller(Controller controller) =>
      RouteGroupBuilder().controller(controller);

  static void resource(
    String name,
    ResourceController controller, {
    List<String>? only,
    List<String>? except,
  }) => router.resource(name, controller, only: only, except: except);

  static void fallback(Function handler) => router.fallback(handler);
}

/// Fluent group attributes: `Route.prefix('admin').middleware([auth]).group(() {...})`.
class RouteGroupBuilder {
  String? _prefix;
  final List<Object> _middleware = [];
  String? _name;
  Controller? _controller;

  RouteGroupBuilder prefix(String prefix) {
    _prefix = prefix;
    return this;
  }

  RouteGroupBuilder middleware(List<Object> middleware) {
    _middleware.addAll(middleware);
    return this;
  }

  RouteGroupBuilder name(String name) {
    _name = name;
    return this;
  }

  RouteGroupBuilder controller(Controller controller) {
    _controller = controller;
    return this;
  }

  void group(void Function() body) => Route.router.group(
    body,
    prefix: _prefix,
    middleware: _middleware,
    name: _name,
    controller: _controller,
  );
}

/// URL for a named route.
String route(String name, [Map<String, Object?> params = const {}]) =>
    Route.router.url(name, params);
