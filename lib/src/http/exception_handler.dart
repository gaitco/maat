import 'dart:async';
import 'dart:convert';

import '../support/log.dart';
import '../validation/validation_exception.dart';
import 'exceptions.dart';
import 'request.dart';
import 'response.dart';

typedef ExceptionReporter = void Function(Object error, StackTrace stackTrace);

class _Renderer {
  _Renderer(this.matches, this.render);
  final bool Function(Object) matches;
  final FutureOr<Response?> Function(Object error, Request request) render;
}

/// Reports and renders every error the kernel catches.
class ExceptionHandler {
  // ignore: prefer_initializing_formals
  ExceptionHandler({required bool Function() debug}) : _debug = debug {
    _reporters.add((error, stackTrace) => Log.error(error, null, stackTrace));
  }

  final bool Function() _debug;
  final List<ExceptionReporter> _reporters = [];
  final List<_Renderer> _renderers = [];
  final List<bool Function(Object)> _dontReport = [
    (e) => e is HttpException,
    (e) => e is ValidationException,
    (e) => e is HttpResponseException,
  ];

  /// Add a reporter. The default `Log.error` reporter always stays, like Laravel's logging.
  void report(ExceptionReporter reporter) => _reporters.add(reporter);

  void render<T extends Object>(
    FutureOr<Response?> Function(T error, Request request) renderer,
  ) => _renderers.add(_Renderer((e) => e is T, (e, r) => renderer(e as T, r)));

  void dontReport<T extends Object>() => _dontReport.add((e) => e is T);

  bool shouldReport(Object error) => !_dontReport.any((m) => m(error));

  Future<Response> handle(
    Request request,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (error is HttpResponseException) {
      return error.response;
    }
    if (shouldReport(error)) {
      for (final reporter in _reporters) {
        // A failing reporter (e.g. the default Log.error hitting an
        // unwritable log path) must not stop other reporters or the
        // response from rendering — Laravel guards Handler::report the
        // same way.
        try {
          reporter(error, stackTrace);
        } catch (_) {
          // ignore: intentionally swallowed, this is the reporting path itself.
        }
      }
    }
    for (final renderer in _renderers) {
      if (!renderer.matches(error)) {
        continue;
      }
      final response = await renderer.render(error, request);
      if (response != null) {
        return response;
      }
    }
    return _renderDefault(request, error, stackTrace);
  }

  Response _renderDefault(
    Request request,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is ValidationException) {
      return _respond(request, 422, {
        'message': error.message,
        'errors': error.errors,
      });
    }
    if (error is HttpException) {
      return _respond(request, error.statusCode, {
        'message': error.message,
      }, error.headers);
    }
    final body = <String, Object?>{'message': 'Server Error'};
    if (_debug()) {
      body['exception'] = error.runtimeType.toString();
      body['message'] = error.toString();
      body['trace'] = const LineSplitter().convert(stackTrace.toString());
    }
    return _respond(request, 500, body);
  }

  Response _respond(
    Request request,
    int status,
    Map<String, Object?> body, [
    Map<String, String> headers = const {},
  ]) {
    if (request.wantsJson) {
      return Response.json(body, status: status, headers: headers);
    }
    final title = '$status ${reasonPhrase(status)}';
    final details = body.entries
        .where((e) => e.key != 'message')
        .map(
          (e) =>
              '<pre>${_escape(e.key)}: ${_escape(e.value is List ? (e.value as List).join('\n') : e.value.toString())}</pre>',
        )
        .join();
    final html =
        '<!doctype html><html><head><meta charset="utf-8"><title>$title</title></head>'
        '<body style="font-family:system-ui;padding:2rem"><h1>$title</h1><p>${_escape(body['message'].toString())}</p>$details</body></html>';
    return Response.html(html, status: status).withHeaders(headers);
  }

  static String _escape(String s) => const HtmlEscape().convert(s);
}
