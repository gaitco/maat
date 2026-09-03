import 'dart:async';

import '../../config/config.dart';
import '../request.dart';
import '../response.dart';
import 'middleware.dart';

/// CORS handling driven by `config('cors')` (or explicit [options]).
class Cors extends Middleware {
  // ignore: prefer_initializing_formals
  Cors({Map<String, dynamic>? options}) : _options = options;

  final Map<String, dynamic>? _options;

  Map<String, dynamic> get _o =>
      _options ?? (config('cors') as Map<String, dynamic>? ?? const {});

  List<String> _list(String key, List<String> fallback) =>
      (_o[key] as List?)?.map((e) => e.toString()).toList() ?? fallback;

  @override
  FutureOr<Response> handle(Request request, Next next) async {
    final origin = request.header('origin');
    if (origin == null || !_pathMatches(request.path)) return next(request);
    final allowedOrigin = _allowedOrigin(origin);
    if (allowedOrigin == null) return next(request);

    final headers = <String, String>{
      'access-control-allow-origin': allowedOrigin,
      'vary': 'Origin',
      if (_o['supports_credentials'] == true)
        'access-control-allow-credentials': 'true',
    };

    if (request.method == 'OPTIONS' &&
        request.header('access-control-request-method') != null) {
      final methods = _list('allowed_methods', ['*']);
      final reqHeaders = _list('allowed_headers', ['*']);
      final maxAge = _o['max_age'];
      return Response.noContent().withHeaders({
        ...headers,
        'access-control-allow-methods': methods.contains('*')
            ? (request.header('access-control-request-method') ?? '*')
            : methods.join(', '),
        'access-control-allow-headers': reqHeaders.contains('*')
            ? (request.header('access-control-request-headers') ?? '*')
            : reqHeaders.join(', '),
        if (maxAge is int && maxAge > 0) 'access-control-max-age': '$maxAge',
      });
    }

    final exposed = _list('exposed_headers', const []);
    final response = await next(request);
    return response.withHeaders({
      ...headers,
      if (exposed.isNotEmpty)
        'access-control-expose-headers': exposed.join(', '),
    });
  }

  bool _pathMatches(String path) {
    final clean = path.replaceFirst(RegExp(r'^/'), '');
    for (final pattern in _list('paths', ['*'])) {
      if (pattern == '*') return true;
      final regex = RegExp(
        '^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$',
      );
      if (regex.hasMatch(clean) || regex.hasMatch(path)) return true;
    }
    return false;
  }

  String? _allowedOrigin(String origin) {
    final allowed = _list('allowed_origins', ['*']);
    if (allowed.contains('*')) {
      return _o['supports_credentials'] == true ? origin : '*';
    }
    return allowed.contains(origin) ? origin : null;
  }
}
