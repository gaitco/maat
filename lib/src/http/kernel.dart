import 'package:shelf/shelf.dart' as shelf;

import '../foundation/application.dart';
import '../routing/router.dart';
import 'exception_handler.dart';
import 'json_resource.dart';
import 'middleware/middleware.dart';
import 'middleware/pipeline.dart';
import 'request.dart';
import 'response.dart';
import 'exceptions.dart';

/// Global middleware → route match → route middleware → handler, errors rendered inside.
class HttpKernel {
  HttpKernel(this.app);
  final Application app;

  Future<Response> handle(Request request) async {
    final exceptions = app.make<ExceptionHandler>();
    final middlewareConfig = app.make<MiddlewareConfig>();
    Future<Response> onError(
      Object error,
      StackTrace stackTrace,
      Request req,
    ) => exceptions.handle(req, error, stackTrace);
    try {
      final global = middlewareConfig.resolveAll(middlewareConfig.global);
      final response = await Pipeline(global, onError: onError).run(request, (
        req,
      ) async {
        final match = app.make<Router>().match(req.method, req.path);
        req
          ..route = match.route
          ..params = match.params;
        final routeMiddleware = middlewareConfig.resolveAll(
          match.route.middlewareList,
        );
        return Pipeline(routeMiddleware, onError: onError).run(req, (r) async {
          final value = await match.route.run(r);
          // Resolved here because this is the only place both the resource
          // and its request are in scope: Response.from is static and
          // request-free, and its toJson() probe cannot call a toJson that
          // requires a Request. Everything still funnels through
          // Response.from, which renders the resulting Map as JSON.
          return Response.from(
            value is JsonResource ? value.resolve(r) : value,
          );
        });
      });
      // Force encoding now, inside this try block, so a body with no
      // toJson() renders as a normal 500 instead of escaping to shelf's
      // raw error page from toShelf()/TestClient later.
      if (!response.isStreaming) response.encodedBody;
      return response;
    } catch (error, stackTrace) {
      return exceptions.handle(request, error, stackTrace);
    }
  }

  Future<shelf.Response> handleShelf(shelf.Request request) async {
    final configuredLimit = app.config.get(
      'http.max_body_bytes',
      Request.defaultMaxBodyBytes,
    );
    final limit = configuredLimit is int && configuredLimit >= 0
        ? configuredLimit
        : Request.defaultMaxBodyBytes;
    try {
      var streamBody = false;
      try {
        streamBody = app
            .make<Router>()
            .match(request.method, request.url.path)
            .route
            .streamsRequestBody;
      } on HttpException {
        // Let the normal kernel path render routing errors through middleware.
      }
      return (await handle(
        streamBody
            ? Request.fromShelfStream(request, maxBodyBytes: limit)
            : await Request.fromShelf(request, maxBodyBytes: limit),
      )).toShelf();
    } on HttpException catch (error, stackTrace) {
      final requestWithoutBody = Request.create(
        method: request.method,
        path: request.requestedUri.toString(),
        headers: request.headers,
      );
      return (await app.make<ExceptionHandler>().handle(
        requestWithoutBody,
        error,
        stackTrace,
      )).toShelf();
    }
  }
}
