import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart' as shelf;

import '../config/config.dart';
import '../routing/route_definition.dart';
import '../validation/form_request.dart';
import '../validation/validator.dart';
import 'exceptions.dart';

/// An incoming HTTP request with Laravel's accessor API. Body is read once.
class Request {
  static const defaultMaxBodyBytes = 10 * 1024 * 1024;

  Request._({
    required this.method,
    required this.uri,
    required Map<String, String> headers,
    required this.ip,
    required String? rawBody,
    required this.bodyStream,
  }) : headers = Map.unmodifiable({
         for (final e in headers.entries) e.key.toLowerCase(): e.value,
       }),
       _rawBody = rawBody {
    _input = rawBody == null ? {} : _parseBody();
  }

  /// Build a request without a server (tests, TestClient).
  factory Request.create({
    String method = 'GET',
    String path = '/',
    Map<String, String> headers = const {},
    String? body,
    Object? json,
    Map<String, String>? form,
    String ip = '127.0.0.1',
  }) {
    final merged = {...headers};
    var raw = body ?? '';
    if (json != null) {
      raw = jsonEncode(json);
      merged.putIfAbsent('content-type', () => 'application/json');
    } else if (form != null) {
      raw = form.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      merged.putIfAbsent(
        'content-type',
        () => 'application/x-www-form-urlencoded',
      );
    }
    return Request._(
      method: method.toUpperCase(),
      uri: Uri.parse('http://localhost$path'),
      headers: merged,
      ip: ip,
      rawBody: raw,
      bodyStream: Stream.value(utf8.encode(raw)),
    );
  }

  static Future<Request> fromShelf(
    shelf.Request request, {
    int maxBodyBytes = defaultMaxBodyBytes,
  }) async {
    final declaredLength = int.tryParse(
      request.headers['content-length'] ?? '',
    );
    if (declaredLength != null && declaredLength > maxBodyBytes) {
      throw PayloadTooLargeHttpException();
    }
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request.read()) {
      length += chunk.length;
      if (length > maxBodyBytes) throw PayloadTooLargeHttpException();
      bytes.add(chunk);
    }
    final bodyBytes = bytes.takeBytes();
    final body = (request.encoding ?? utf8).decode(bodyBytes);
    final info = request.context['shelf.io.connection_info'];
    final ip = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : '127.0.0.1';
    return Request._(
      method: request.method.toUpperCase(),
      uri: request.requestedUri,
      headers: request.headers,
      ip: ip,
      rawBody: body,
      bodyStream: Stream.value(bodyBytes),
    );
  }

  /// Build a request whose body is consumed by the route as a stream.
  static Request fromShelfStream(
    shelf.Request request, {
    int maxBodyBytes = defaultMaxBodyBytes,
  }) {
    final declaredLength = int.tryParse(
      request.headers['content-length'] ?? '',
    );
    if (declaredLength != null && declaredLength > maxBodyBytes) {
      throw PayloadTooLargeHttpException();
    }
    final info = request.context['shelf.io.connection_info'];
    return Request._(
      method: request.method.toUpperCase(),
      uri: request.requestedUri,
      headers: request.headers,
      ip: info is HttpConnectionInfo ? info.remoteAddress.address : '127.0.0.1',
      rawBody: null,
      bodyStream: _limited(request.read(), maxBodyBytes),
    );
  }

  static Stream<List<int>> _limited(
    Stream<List<int>> source,
    int maxBodyBytes,
  ) async* {
    var length = 0;
    await for (final chunk in source) {
      length += chunk.length;
      if (length > maxBodyBytes) throw PayloadTooLargeHttpException();
      yield chunk;
    }
  }

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String ip;
  final String? _rawBody;

  /// The buffered body. Streaming routes must consume [bodyStream] instead.
  String get rawBody =>
      _rawBody ??
      (throw StateError(
        'This route streams its request body; consume Request.bodyStream.',
      ));

  final Stream<List<int>> bodyStream;
  bool get isBodyBuffered => _rawBody != null;

  /// The matched route, set by the kernel.
  RouteDefinition? route;

  /// Route parameters, set by the kernel.
  Map<String, String> params = {};

  /// Bag for middleware to attach data (e.g. the authenticated user).
  final Map<String, Object?> attributes = {};

  /// The [attributes] key a route-model binding stores its resolved model
  /// under. Namespaced so a binding named `user` cannot collide with an
  /// authentication middleware that also writes `attributes['user']`.
  static String boundAttribute(String name) => '$_boundPrefix$name';

  static const _boundPrefix = 'binding:';

  /// The model a route-model binding resolved for route parameter [name].
  ///
  /// Throws instead of returning null: an unbound parameter is a wiring
  /// mistake, and a null here would surface later as an unrelated null error
  /// somewhere in the handler. The message lists what *was* bound so a typo
  /// ("widgets" for "widget") is distinguishable from a binding that never
  /// ran at all.
  T bound<T>(String name) {
    final value = attributes[boundAttribute(name)];
    if (value != null) return value as T;
    final resolved = [
      for (final key in attributes.keys)
        if (key.startsWith(_boundPrefix)) key.substring(_boundPrefix.length),
    ];
    String list(Iterable<String> names) =>
        names.isEmpty ? '(none)' : names.join(', ');
    throw StateError(
      'Route parameter [$name] is not bound to a model. '
      'Bound on this request: ${list(resolved)}. '
      'Route parameters: ${list(params.keys)}. '
      "Register the binding with ModelBinding.bind('$name', Model.def) and "
      'add ModelBinding.middleware() to the route as route middleware — as '
      'global middleware it runs before the router matches, so no route '
      'parameters exist yet.',
    );
  }

  late Map<String, dynamic> _input;
  Object? _json;
  bool _jsonParsed = false;

  /// The URI as the client sees it, honouring `X-Forwarded-*` when the
  /// request arrived through a trusted proxy.
  ///
  /// [uri] describes the hop *this process* accepted. Behind nginx, Herd or
  /// a load balancer that is plain HTTP on a private port, so every
  /// absolute URL built from it — a pagination link, a redirect — sends an
  /// HTTPS client back to HTTP.
  ///
  /// The headers are honoured only from an address listed in
  /// `app.trusted_proxies` (a comma-separated string, a list, or `*`).
  /// Anywhere else they are attacker-controlled: a forged
  /// `X-Forwarded-Host` rewrites every absolute URL the application
  /// generates, which is how password-reset links get redirected and
  /// caches get poisoned. Unset means trust nothing, which is why the
  /// default is to return [uri] unchanged.
  Uri get publicUri {
    if (!_behindTrustedProxy) return uri;
    var result = uri;
    // First value only: each hop appends, so the list reads
    // `client, proxy1, proxy2` and the client's own claim is the head.
    final proto = _forwarded('x-forwarded-proto');
    if (proto == 'http' || proto == 'https') {
      result = result.replace(scheme: proto);
    }
    final host = _forwarded('x-forwarded-host');
    if (host != null && host.isNotEmpty) {
      final colon = host.lastIndexOf(':');
      final name = colon == -1 ? host : host.substring(0, colon);
      final port = colon == -1 ? null : int.tryParse(host.substring(colon + 1));
      // The scheme's own default, not 0: `Uri` drops a default port when
      // it prints, but renders a literal `:0`. The scheme is already the
      // forwarded one here, so https defaults to 443.
      result = result.replace(
        host: name,
        port: port ?? (result.scheme == 'https' ? 443 : 80),
      );
    }
    return result;
  }

  String? _forwarded(String name) => header(name)?.split(',').first.trim();

  bool get _behindTrustedProxy {
    final trusted = config('app.trusted_proxies');
    final entries = switch (trusted) {
      null => const <String>[],
      final List<Object?> list => [for (final e in list) e.toString().trim()],
      final Object value => value.toString().split(',').map((e) => e.trim()),
    };
    return entries.any((e) => e == '*' || e == ip);
  }

  String get path => uri.path;
  String? param(String name) => params[name];
  String? header(String name) => headers[name.toLowerCase()];

  String? bearerToken() {
    final value = header('authorization');
    if (value == null || !value.toLowerCase().startsWith('bearer ')) {
      return null;
    }
    return value.substring(7).trim();
  }

  bool get isJson => (header('content-type') ?? '').contains('json');
  bool get wantsJson =>
      (header('accept') ?? '').contains('application/json') ||
      path.startsWith('/api');
  bool get expectsJson => wantsJson || isJson;

  /// The decoded JSON body, or null when the body is not JSON.
  dynamic get json {
    if (!_jsonParsed) {
      _jsonParsed = true;
      if (isJson && rawBody.isNotEmpty) {
        try {
          _json = jsonDecode(rawBody);
        } on FormatException {
          _json = null;
        }
      }
    }
    return _json;
  }

  Map<String, String> get queryAll => uri.queryParameters;
  String? query(String key, [String? defaultValue]) =>
      uri.queryParameters[key] ?? defaultValue;

  /// Query parameters merged with body input; body wins.
  Map<String, dynamic> all() => {...uri.queryParameters, ..._input};

  /// `input('user.name')` dot access; `input()` returns [all].
  dynamic input([String? key, Object? defaultValue]) {
    if (key == null) return all();
    dynamic node = all();
    for (final segment in key.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else if (node is List &&
          int.tryParse(segment) != null &&
          int.parse(segment) < node.length) {
        node = node[int.parse(segment)];
      } else {
        return defaultValue;
      }
    }
    return node;
  }

  Map<String, dynamic> only(List<String> keys) {
    final data = all();
    return {
      for (final k in keys)
        if (data.containsKey(k)) k: data[k],
    };
  }

  Map<String, dynamic> except(List<String> keys) {
    final data = all()..removeWhere((k, _) => keys.contains(k));
    return data;
  }

  bool has(String key) => input(key, _absent) != _absent;

  bool filled(String key) {
    final v = input(key);
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  bool boolean(String key) {
    final v = input(key);
    if (v is bool) return v;
    if (v is num) return v != 0;
    return const {
      '1',
      'true',
      'on',
      'yes',
    }.contains(v?.toString().toLowerCase());
  }

  int? integer(String key, [int? defaultValue]) {
    final v = input(key);
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? defaultValue;
  }

  String? string(String key) => input(key)?.toString();

  /// Validate [all] against [rules]; returns validated data or throws ValidationException.
  Future<Map<String, dynamic>> validate(
    Map<String, Object> rules, {
    Map<String, String> messages = const {},
    Map<String, String> attributes = const {},
  }) async => Validator(
    all(),
    rules,
    messages: messages,
    attributes: attributes,
  ).validateAsync();

  Future<Map<String, dynamic>> validateWith(FormRequest form) async {
    if (!form.authorize(this)) {
      throw ForbiddenHttpException('This action is unauthorized.');
    }
    return validate(
      form.rules(),
      messages: form.messages(),
      attributes: form.attributes(),
    );
  }

  void merge(Map<String, dynamic> data) => _input.addAll(data);

  void replace(Map<String, dynamic> data) => _input = {...data};

  static const _absent = Object();

  Map<String, dynamic> _parseBody() {
    if (rawBody.isEmpty) return {};
    if (isJson) {
      final decoded = json;
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    }
    final type = header('content-type') ?? '';
    if (type.contains('application/x-www-form-urlencoded')) {
      final result = <String, dynamic>{};
      for (final pair in rawBody.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final key = Uri.decodeQueryComponent(
          eq < 0 ? pair : pair.substring(0, eq),
        );
        final value = eq < 0
            ? ''
            : Uri.decodeQueryComponent(pair.substring(eq + 1));
        if (key.endsWith('[]')) {
          final name = key.substring(0, key.length - 2);
          (result[name] ??= <String>[]).add(value);
        } else {
          result[key] = value;
        }
      }
      return result;
    }
    return {};
  }
}
