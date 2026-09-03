import 'response.dart';

const _reasons = <int, String>{
  200: 'OK',
  201: 'Created',
  204: 'No Content',
  301: 'Moved Permanently',
  302: 'Found',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  409: 'Conflict',
  413: 'Payload Too Large',
  419: 'Page Expired',
  422: 'Unprocessable Content',
  429: 'Too Many Requests',
  500: 'Internal Server Error',
  503: 'Service Unavailable',
};

String reasonPhrase(int status) => _reasons[status] ?? 'Unknown Status';

/// An error that renders as an HTTP response with [statusCode].
class HttpException implements Exception {
  HttpException(this.statusCode, [String? message, this.headers = const {}])
    : message = message ?? reasonPhrase(statusCode);

  final int statusCode;
  final String message;
  final Map<String, String> headers;

  @override
  String toString() => 'HttpException($statusCode): $message';
}

class NotFoundHttpException extends HttpException {
  NotFoundHttpException([String? message]) : super(404, message);
}

class UnauthorizedHttpException extends HttpException {
  UnauthorizedHttpException([String? message]) : super(401, message);
}

class ForbiddenHttpException extends HttpException {
  ForbiddenHttpException([String? message]) : super(403, message);
}

class MethodNotAllowedHttpException extends HttpException {
  MethodNotAllowedHttpException(List<String> allowed)
    : super(405, null, {'allow': allowed.join(', ')});
}

class TooManyRequestsHttpException extends HttpException {
  TooManyRequestsHttpException([
    String? message,
    Map<String, String> headers = const {},
  ]) : super(429, message, headers);
}

class PayloadTooLargeHttpException extends HttpException {
  PayloadTooLargeHttpException([String? message]) : super(413, message);
}

/// Short-circuit the request with an explicit [response].
class HttpResponseException implements Exception {
  HttpResponseException(this.response);
  final Response response;
}

/// Laravel's `abort()`: throw an [HttpException].
Never abort(
  int status, [
  String? message,
  Map<String, String> headers = const {},
]) => throw HttpException(status, message, headers);
