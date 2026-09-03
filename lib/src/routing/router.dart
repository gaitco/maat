import '../http/controller.dart';
import '../http/exceptions.dart';
import 'route_definition.dart';

class RouteMatch {
  RouteMatch(this.route, this.params);
  final RouteDefinition route;
  final Map<String, String> params;
}

class _Group {
  _Group(this.prefix, this.middleware, this.namePrefix, this.controller);
  final String prefix;
  final List<Object> middleware;
  final String namePrefix;
  final Controller? controller;
}

class _IndexedRoute {
  _IndexedRoute(this.order, this.route);
  final int order;
  final RouteDefinition route;
}

/// Registers routes (with nested groups) and matches requests against them.
class Router {
  final List<RouteDefinition> _routes = [];
  final Map<String, List<_IndexedRoute>> _staticRoutes = {};
  final Map<String?, List<_IndexedRoute>> _dynamicRoutes = {};
  final Map<String, RouteDefinition> _named = {};
  final List<_Group> _groups = [];
  RouteDefinition? _fallback;

  List<RouteDefinition> get routes => List.unmodifiable(_routes);

  /// [handler] is a function, or a single-action [Controller] whose `call`
  /// method becomes the function. Controller middleware is added when the
  /// controller is known: an invokable handler, or the enclosing
  /// `Route.controller(...)` group.
  RouteDefinition add(List<String> methods, String uri, Object handler) {
    final prefix = _groups.map((g) => g.prefix).join();
    final middleware = [for (final g in _groups) ...g.middleware];
    final namePrefix = _groups.map((g) => g.namePrefix).join();
    final Function action;
    if (handler is Controller) {
      action = _invoke(handler, uri);
      middleware.addAll(controllerMiddlewareFor(handler, action));
    } else if (handler is Function) {
      action = handler;
      final controller = _groups
          .lastWhere((g) => g.controller != null, orElse: () => _noGroup)
          .controller;
      if (controller != null) {
        middleware.addAll(controllerMiddlewareFor(controller, action));
      }
    } else {
      throw ArgumentError(
        'Route handler for [$uri] must be a function or a Controller with a '
        'call() method, got ${handler.runtimeType}',
      );
    }
    final route = RouteDefinition(
      methods,
      '$prefix/$uri',
      action,
      middleware: middleware,
      namePrefix: namePrefix,
    )..router = this;
    final indexed = _IndexedRoute(_routes.length, route);
    _routes.add(route);
    final index = route.isStatic ? _staticRoutes : _dynamicRoutes;
    final key = route.isStatic ? route.uri : route.firstStaticSegment;
    index.putIfAbsent(key, () => []).add(indexed);
    return route;
  }

  static final _noGroup = _Group('', const [], '', null);

  /// Tear off `call` from a single-action controller without reflection;
  /// `dynamic` dispatch resolves the method whatever its parameter list.
  static Function _invoke(Controller controller, String uri) {
    try {
      return (controller as dynamic).call as Function;
    } on NoSuchMethodError {
      throw ArgumentError(
        '${controller.runtimeType} used as the handler for [$uri] must '
        'define call(Request request) to be a single-action controller',
      );
    }
  }

  void group(
    void Function() body, {
    String? prefix,
    List<Object>? middleware,
    String? name,
    Controller? controller,
  }) {
    final cleanPrefix = prefix == null
        ? ''
        : '/${prefix.replaceAll(RegExp(r'^/+|/+$'), '')}';
    _groups.add(
      _Group(
        cleanPrefix == '/' ? '' : cleanPrefix,
        middleware ?? const [],
        name ?? '',
        controller,
      ),
    );
    try {
      body();
    } finally {
      _groups.removeLast();
    }
  }

  /// Register index/store/show/update/destroy for [controller] under `/name`.
  void resource(
    String name,
    ResourceController controller, {
    List<String>? only,
    List<String>? except,
  }) {
    final actions = ['index', 'store', 'show', 'update', 'destroy']
        .where((a) => only == null || only.contains(a))
        .where((a) => except == null || !except.contains(a));
    final base = name.replaceAll(RegExp(r'^/+|/+$'), '');
    group(controller: controller, () {
      for (final action in actions) {
        _resourceAction(base, action, controller);
      }
    });
  }

  void _resourceAction(
    String base,
    String action,
    ResourceController controller,
  ) {
    switch (action) {
      case 'index':
        add(['GET', 'HEAD'], base, controller.index).name('$base.index');
      case 'store':
        add(['POST'], base, controller.store).name('$base.store');
      case 'show':
        add(['GET', 'HEAD'], '$base/{id}', controller.show).name('$base.show');
      case 'update':
        add(
          ['PUT', 'PATCH'],
          '$base/{id}',
          controller.update,
        ).name('$base.update');
      case 'destroy':
        add(['DELETE'], '$base/{id}', controller.destroy).name('$base.destroy');
    }
  }

  void fallback(Function handler) {
    _fallback =
        RouteDefinition(
            ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
            '/{fallback?}',
            handler,
          )
          ..router = this
          ..where('fallback', '.*');
  }

  /// Throws [NotFoundHttpException] or [MethodNotAllowedHttpException].
  RouteMatch match(String method, String path) {
    final upper = method.toUpperCase();
    final normalizedPath = RouteDefinition.normalizeUri(path);
    final candidates = <_IndexedRoute>[
      ...?_staticRoutes[normalizedPath],
      ...?_dynamicRoutes[_firstSegment(normalizedPath)],
      ...?_dynamicRoutes[null],
    ]..sort((a, b) => a.order.compareTo(b.order));
    final allowed = <String>{};
    for (final candidate in candidates) {
      final route = candidate.route;
      final params = route.isStatic
          ? const <String, String>{}
          : route.match(path);
      if (params == null) continue;
      if (route.allows(upper)) return RouteMatch(route, params);
      allowed.addAll(route.methods);
    }
    if (allowed.isNotEmpty) {
      throw MethodNotAllowedHttpException(allowed.toList());
    }
    final fallback = _fallback;
    if (fallback != null) {
      return RouteMatch(fallback, fallback.match(path) ?? {});
    }
    throw NotFoundHttpException();
  }

  static String _firstSegment(String path) =>
      path == '/' ? '' : path.substring(1).split('/').first;

  void registerName(RouteDefinition route) {
    final name = route.routeName!;
    final existing = _named[name];
    if (existing != null && !identical(existing, route)) {
      throw StateError(
        'Route name [$name] is already used by [${existing.uri}]',
      );
    }
    _named[name] = route;
  }

  bool hasNamed(String name) => _named.containsKey(name);

  String url(String name, [Map<String, Object?> params = const {}]) {
    final route = _named[name];
    if (route == null) throw ArgumentError('Route [$name] not defined.');
    return route.url(params);
  }
}
