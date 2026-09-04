import '../api/route_contract.dart';
import '../api/schema.dart';
import '../http/request.dart';
import '../validation/form_request.dart';
import 'router.dart';

/// One registered route: methods, URI pattern, handler, middleware, name.
class RouteDefinition {
  RouteDefinition(
    List<String> methods,
    String uri,
    this.handler, {
    List<Object> middleware = const [],
    this._namePrefix = '',
  }) : methods = List.unmodifiable(methods.map((m) => m.toUpperCase())),
       uri = normalizeUri(uri),
       middlewareList = [...middleware] {
    _compile();
    _arity = _detectArity(handler, paramNames.length, this.uri);
  }

  final List<String> methods;
  final String uri;
  final Function handler;
  final List<Object> middlewareList;
  final String _namePrefix;
  final Map<String, String> _wheres = {};
  late RegExp _pattern;
  late List<String> paramNames;
  late int _arity;
  bool _streamsRequestBody = false;
  String? _name;
  Router? router;

  /// What this route accepts and returns, once something declares it.
  /// `null` until then, which is also what keeps the route out of the
  /// generated API document.
  RouteContract? contract;

  RouteContract get _contract => contract ??= RouteContract();

  /// A one-line title for the operation.
  RouteDefinition summary(String text) {
    _contract.summary = text;
    return this;
  }

  /// The longer prose shown under the summary.
  RouteDefinition describe(String text) {
    _contract.description = text;
    return this;
  }

  RouteDefinition tags(List<String> names) {
    _contract.tags.addAll(names);
    return this;
  }

  /// Overrides the generated operation id, which is also the generated
  /// client's method name.
  RouteDefinition operation(String id) {
    _contract.operationId = id;
    return this;
  }

  /// Types the URI's `{placeholders}` with validation rules. Path parameters
  /// always arrive as strings; this is what lets the generated client take an
  /// `int id` and the document say `integer`.
  RouteDefinition params(Map<String, Object> rules) {
    for (final name in rules.keys) {
      if (!paramNames.contains(name)) {
        throw ArgumentError(
          'Route [$uri] has no parameter named [$name]. Its parameters are '
          '${paramNames.isEmpty ? '(none)' : paramNames.join(', ')}.',
        );
      }
    }
    _contract.pathRules.addAll(rules);
    return this;
  }

  /// Query string rules, in the same form the validator takes.
  RouteDefinition query(Map<String, Object> rules) {
    _contract.queryRules.addAll(rules);
    return this;
  }

  /// The JSON request body, as a rule map or the [FormRequest] the handler
  /// validates with.
  RouteDefinition body(Object rules) {
    if (rules is FormRequest) {
      _contract.useFormRequest(rules);
    } else if (rules is Map<String, Object>) {
      _contract.bodyRules.addAll(rules);
    } else {
      throw ArgumentError(
        'Route [$uri] body must be a rule map or a FormRequest, got '
        '${rules.runtimeType}',
      );
    }
    return this;
  }

  /// Declares one response. Call it once per status a client should expect;
  /// `ApiSchema.none()` is an empty body such as a 204.
  RouteDefinition responds(
    ApiSchema schema, {
    int status = 200,
    String? description,
  }) {
    if (status < 100 || status > 599) {
      throw ArgumentError.value(
        status,
        'status',
        'An API response status must be between 100 and 599.',
      );
    }
    _contract.responses[status] = ApiResponse(
      status,
      schema,
      description: description,
    );
    return this;
  }

  RouteDefinition deprecate() {
    _contract.deprecated = true;
    return this;
  }

  String? get routeName => _name;
  bool get isStatic => paramNames.isEmpty;
  bool get streamsRequestBody => _streamsRequestBody;

  /// The first literal path segment, or null for a leading parameter.
  String? get firstStaticSegment {
    if (uri == '/') return '';
    final segment = uri.substring(1).split('/').first;
    return segment.startsWith('{') ? null : segment;
  }

  static String normalizeUri(String uri) {
    var u = uri.trim().replaceAll(RegExp(r'/+'), '/');
    if (!u.startsWith('/')) u = '/$u';
    if (u.length > 1 && u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  RouteDefinition name(String name) {
    _name = '$_namePrefix$name';
    router?.registerName(this);
    return this;
  }

  RouteDefinition middleware(List<Object> middleware) {
    middlewareList.addAll(middleware);
    return this;
  }

  /// Let the handler consume [Request.bodyStream] without buffering the body.
  RouteDefinition streamRequestBody() {
    _streamsRequestBody = true;
    return this;
  }

  RouteDefinition where(String param, String pattern) {
    _wheres[param] = pattern;
    _compile();
    return this;
  }

  bool allows(String method) =>
      methods.contains(method) || (method == 'HEAD' && methods.contains('GET'));

  /// Returns captured params when [path] matches, else null.
  Map<String, String>? match(String path) {
    final m = _pattern.firstMatch(normalizeUri(path));
    if (m == null) return null;
    final params = <String, String>{};
    for (var i = 0; i < paramNames.length; i++) {
      final value = m.group(i + 1);
      if (value != null) params[paramNames[i]] = Uri.decodeComponent(value);
    }
    return params;
  }

  /// Build a URL for this route. Extra params become a query string.
  String url([Map<String, Object?> params = const {}]) {
    final remaining = {...params};
    final buffer = StringBuffer();
    for (final segment in uri.split('/').skip(1)) {
      final m = RegExp(r'^\{(\w+)(\?)?\}$').firstMatch(segment);
      if (m == null) {
        buffer.write('/$segment');
        continue;
      }
      final value = remaining.remove(m[1]);
      if (value == null) {
        if (m[2] == '?') continue;
        throw ArgumentError(
          'Missing required parameter [${m[1]}] for route [$uri]',
        );
      }
      buffer.write('/${Uri.encodeComponent(value.toString())}');
    }
    var result = buffer.isEmpty ? '/' : buffer.toString();
    if (remaining.isNotEmpty) {
      result +=
          '?${Uri(queryParameters: remaining.map((k, v) => MapEntry(k, v.toString()))).query}';
    }
    return result;
  }

  /// Invoke the handler with the request and as many positional params as it accepts.
  Future<Object?> run(Request request) async {
    if (_arity < 0) return await Function.apply(handler, const []);
    final values = <String>[];
    for (final name in paramNames) {
      final v = request.params[name];
      if (v == null) break;
      values.add(v);
    }
    final args = <Object?>[request, ...values.take(_arity)];
    return await Function.apply(handler, args);
  }

  void _compile() {
    paramNames = [];
    final buffer = StringBuffer('^');
    if (uri == '/') {
      _pattern = RegExp(r'^/?$');
      return;
    }
    for (final segment in uri.split('/').skip(1)) {
      final m = RegExp(r'^\{(\w+)(\?)?\}$').firstMatch(segment);
      if (m == null) {
        buffer.write('/${RegExp.escape(segment)}');
        continue;
      }
      final name = m[1]!;
      final optional = m[2] == '?';
      final pattern = _wheres[name] ?? '[^/]+';
      paramNames.add(name);
      buffer.write(optional ? '(?:/($pattern))?' : '/($pattern)');
    }
    buffer.write(r'/?$');
    _pattern = RegExp(buffer.toString());
  }

  /// Detect how many String params [handler] accepts after the Request, using
  /// `is` checks on function types (AOT-safe, no reflection). -1 means no params at all.
  static int _detectArity(Function handler, int available, String uri) {
    if (available >= 4 &&
        handler is Object? Function(Request, String, String, String, String)) {
      return 4;
    }
    if (available >= 3 &&
        handler is Object? Function(Request, String, String, String)) {
      return 3;
    }
    if (available >= 2 &&
        handler is Object? Function(Request, String, String)) {
      return 2;
    }
    if (available >= 1 && handler is Object? Function(Request, String)) {
      return 1;
    }
    if (handler is Object? Function(Request)) return 0;
    if (handler is Object? Function()) return -1;
    throw ArgumentError(
      'Route handler for [$uri] must be a function taking (Request request) followed by up to '
      '$available String parameters. Declare optional route params as optional positional String? parameters.',
    );
  }
}
