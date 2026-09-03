import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;

/// An HTTP response. Immutable; fluent methods return copies.
class Response {
  Response(this.body, {int status = 200, Map<String, String>? headers})
    : statusCode = status,
      headers = Map.unmodifiable({
        for (final e in (headers ?? {}).entries) e.key.toLowerCase(): e.value,
      });

  Response.json(Object? data, {int status = 200, Map<String, String>? headers})
    : this(
        encodeJson(data),
        status: status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...?headers,
        },
      );

  Response.text(String body, {int status = 200})
    : this(
        body,
        status: status,
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );

  Response.html(String body, {int status = 200})
    : this(
        body,
        status: status,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  Response.redirect(String location, {int status = 302})
    : this('', status: status, headers: {'location': location});

  Response.noContent() : this('', status: 204);

  /// A binary body — an image, a font, a compiled stylesheet.
  ///
  /// [encodedBody] decodes these bytes as UTF-8 so text assertions in
  /// tests keep working, but [toShelf] hands the bytes to the server
  /// untouched: re-encoding a PNG through a Dart `String` corrupts every
  /// byte outside the ASCII range.
  Response.bytes(
    List<int> body, {
    int status = 200,
    Map<String, String>? headers,
  }) : this(body, status: status, headers: headers);

  /// A body produced over time, without first collecting it in memory.
  Response.stream(
    Stream<List<int>> body, {
    int status = 200,
    Map<String, String>? headers,
  }) : this(body, status: status, headers: headers);

  final Object? body;
  final int statusCode;
  final Map<String, String> headers;

  bool get isStreaming => body is Stream<List<int>>;

  Response status(int code) => Response(body, status: code, headers: headers);

  Response header(String name, String value) => withHeaders({name: value});

  Response withHeaders(Map<String, String> extra) =>
      Response(body, status: statusCode, headers: {...headers, ...extra});

  /// Normalize whatever a route handler returned into a [Response].
  static Response from(Object? value) {
    if (value is Response) return value;
    if (value == null) return Response.noContent();
    if (value is String) return Response.html(value);
    if (value is Map || value is Iterable) return Response.json(value);
    if (_hasToJson(value)) return Response.json(value);
    return Response.text(value.toString());
  }

  static String encodeJson(Object? data) =>
      jsonEncode(data, toEncodable: _toEncodable);

  static Object? _toEncodable(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (_hasToJson(value)) return (value as dynamic).toJson();
    throw JsonUnsupportedObjectError(value);
  }

  static bool _hasToJson(Object? value) {
    if (value == null) return false;
    try {
      (value as dynamic).toJson();
      return true;
    } on NoSuchMethodError {
      return false;
    }
  }

  /// The body actually sent over the wire: a `String` body passes through,
  /// `null` becomes `''`, anything else (e.g. a bare `Response({'a': 1})`
  /// that skipped [Response.json]) is JSON-encoded. Used by both [toShelf]
  /// and `TestClient` so production and tests always agree.
  String get encodedBody {
    if (body == null) return '';
    if (body is String) return body as String;
    if (body is List<int>) {
      return utf8.decode(body as List<int>, allowMalformed: true);
    }
    return encodeJson(body);
  }

  /// Headers actually sent, with a JSON content type added when [encodedBody]
  /// had to JSON-encode a non-string body and none was set already.
  Map<String, String> get sentHeaders {
    if (body is String || body == null || body is List<int> || isStreaming) {
      return headers;
    }
    if (headers.containsKey('content-type')) return headers;
    return {...headers, 'content-type': 'application/json; charset=utf-8'};
  }

  shelf.Response toShelf() => shelf.Response(
    statusCode,
    body: body is List<int> || isStreaming ? body : encodedBody,
    headers: sentHeaders,
  );
}
