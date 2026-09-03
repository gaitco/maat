import '../request.dart';
import '../response.dart';
import 'middleware.dart';

typedef PipelineErrorHandler =
    Future<Response> Function(
      Object error,
      StackTrace stackTrace,
      Request request,
    );

/// Folds a middleware list into nested closures around [run]'s destination.
/// With [onError], exceptions become responses inside the pipeline so outer
/// middleware still run (Illuminate\Routing\Pipeline::handleException).
class Pipeline {
  Pipeline(this._middleware, {PipelineErrorHandler? onError})
    // ignore: prefer_initializing_formals
    : _onError = onError;

  final List<Middleware> _middleware;
  final PipelineErrorHandler? _onError;

  Future<Response> run(Request request, Next destination) async {
    var next = _guard(destination);
    for (final middleware in _middleware.reversed) {
      final inner = next;
      next = _guard((req) => middleware.handle(req, inner));
    }
    return await next(request);
  }

  Next _guard(Next step) {
    final onError = _onError;
    if (onError == null) return step;
    return (req) async {
      try {
        return await step(req);
      } catch (error, stackTrace) {
        return onError(error, stackTrace, req);
      }
    };
  }
}
