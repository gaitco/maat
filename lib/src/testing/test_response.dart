import 'dart:convert';

class TestClientAssertionError extends Error {
  TestClientAssertionError(this.message);
  final String message;
  @override
  String toString() => 'TestClientAssertionError: $message';
}

/// Response wrapper with Laravel-style chainable assertions.
class TestResponse {
  TestResponse(this.statusCode, this.body, this.headers);

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  dynamic get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw TestClientAssertionError(
        'Response body is not valid JSON: ${_truncated(body)}',
      );
    }
  }

  TestResponse assertStatus(int expected) => _check(
    statusCode == expected,
    'Expected status $expected but got $statusCode. Body: $body',
  );
  TestResponse assertOk() => assertStatus(200);
  TestResponse assertCreated() => assertStatus(201);
  TestResponse assertNoContent() => assertStatus(204);
  TestResponse assertNotFound() => assertStatus(404);
  TestResponse assertUnauthorized() => assertStatus(401);
  TestResponse assertForbidden() => assertStatus(403);
  TestResponse assertUnprocessable() => assertStatus(422);

  /// Every key in [subset] must be present in the JSON body with an equal value.
  TestResponse assertJson(Map<String, Object?> subset) {
    final decoded = json;
    _check(decoded is Map, 'Response is not a JSON object: $body');
    final map = decoded as Map;
    for (final e in subset.entries) {
      _check(
        map.containsKey(e.key),
        'JSON key [${e.key}] expected ${jsonEncode(e.value)} but the key is missing. Body: $body',
      );
      _check(
        _deepEquals(map[e.key], e.value),
        'JSON key [${e.key}] expected ${jsonEncode(e.value)} but got ${jsonEncode(map[e.key])}',
      );
    }
    return this;
  }

  TestResponse assertJsonPath(String path, Object? expected) {
    dynamic node = json;
    for (final segment in path.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else if (node is List &&
          int.tryParse(segment) != null &&
          int.parse(segment) < node.length) {
        node = node[int.parse(segment)];
      } else {
        throw TestClientAssertionError('JSON path [$path] not found in $body');
      }
    }
    return _check(
      _deepEquals(node, expected),
      'JSON path [$path] expected ${jsonEncode(expected)} but got ${jsonEncode(node)}',
    );
  }

  TestResponse assertJsonValidationErrors(List<String> fields) {
    assertStatus(422);
    final errors = (json as Map)['errors'] as Map? ?? {};
    for (final f in fields) {
      _check(
        errors.containsKey(f),
        'Expected validation error for [$f]; got ${errors.keys.toList()}',
      );
    }
    return this;
  }

  TestResponse assertJsonMissingValidationErrors([List<String>? fields]) {
    final decoded = json;
    final errors = decoded is Map ? (decoded['errors'] as Map? ?? {}) : {};
    if (fields == null) {
      return _check(
        errors.isEmpty,
        'Unexpected validation errors: ${errors.keys.toList()}',
      );
    }
    for (final f in fields) {
      _check(!errors.containsKey(f), 'Unexpected validation error for [$f]');
    }
    return this;
  }

  TestResponse assertHeader(String name, String value) => _check(
    headers[name.toLowerCase()] == value,
    'Header [$name] expected [$value] but got [${headers[name.toLowerCase()]}]',
  );

  TestResponse assertHeaderContains(String name, String fragment) => _check(
    (headers[name.toLowerCase()] ?? '').contains(fragment),
    'Header [$name] expected to contain [$fragment] but got [${headers[name.toLowerCase()]}]',
  );

  TestResponse assertSee(String text) => _check(
    body.contains(text),
    'Expected body to contain [$text]. Body: $body',
  );

  TestResponse assertRedirect([String? location]) {
    _check(
      statusCode >= 300 && statusCode < 400,
      'Expected a redirect but got $statusCode',
    );
    if (location != null) assertHeader('location', location);
    return this;
  }

  TestResponse _check(bool condition, String message) {
    if (!condition) throw TestClientAssertionError(message);
    return this;
  }

  static bool _deepEquals(Object? a, Object? b) =>
      jsonEncode(a) == jsonEncode(b);

  static String _truncated(String s) =>
      s.length > 200 ? '${s.substring(0, 200)}...' : s;
}
