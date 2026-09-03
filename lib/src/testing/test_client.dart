import '../foundation/application.dart';
import '../http/kernel.dart';
import '../http/request.dart';
import 'test_response.dart';

/// Calls the HTTP kernel in-process, no sockets. Laravel's `$this->get('/')`.
class TestClient {
  TestClient(this.app, [Map<String, String>? headers])
    : _headers = {...?headers};

  final Application app;
  final Map<String, String> _headers;

  TestClient withHeader(String name, String value) =>
      TestClient(app, {..._headers, name: value});
  TestClient withHeaders(Map<String, String> headers) =>
      TestClient(app, {..._headers, ...headers});
  TestClient withToken(String token) =>
      withHeader('authorization', 'Bearer $token');

  Future<TestResponse> get(String path, {Map<String, String>? headers}) =>
      _send('GET', path, headers: headers);

  Future<TestResponse> post(
    String path, {
    Map<String, String>? form,
    Map<String, String>? headers,
  }) => _send('POST', path, form: form ?? const {}, headers: headers);

  Future<TestResponse> delete(String path, {Map<String, String>? headers}) =>
      _send('DELETE', path, headers: headers);

  Future<TestResponse> postJson(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => json('POST', path, body, headers);
  Future<TestResponse> putJson(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => json('PUT', path, body, headers);
  Future<TestResponse> patchJson(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => json('PATCH', path, body, headers);
  Future<TestResponse> deleteJson(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => json('DELETE', path, body, headers);

  Future<TestResponse> json(
    String method,
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => _send(
    method,
    path,
    json: body ?? const <String, Object?>{},
    headers: {'accept': 'application/json', ...?headers},
  );

  Future<TestResponse> _send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? form,
    Map<String, String>? headers,
  }) async {
    final request = Request.create(
      method: method,
      path: path,
      headers: {..._headers, ...?headers},
      json: json,
      form: form,
    );
    final response = await app.make<HttpKernel>().handle(request);
    final body = response.isStreaming
        ? await response.toShelf().readAsString()
        : response.encodedBody;
    return TestResponse(response.statusCode, body, response.sentHeaders);
  }
}
