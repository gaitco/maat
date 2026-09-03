import 'dart:async';

import '../exceptions.dart';
import '../request.dart';
import '../response.dart';
import 'middleware.dart';

/// Fixed-window rate limiter keyed by ip + route.
// ponytail: in-memory, per-isolate, evicts expired windows past a size
// threshold instead of an LRU; a cache-backed store lands in Phase 4.
class ThrottleRequests extends Middleware {
  ThrottleRequests({
    this.maxAttempts = 60,
    this.decayMinutes = 1,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxAttempts;
  final int decayMinutes;
  final DateTime Function() _now;
  final Map<String, _Window> _windows = {};

  /// Above this many distinct ip|route keys, sweep expired windows before adding more.
  static const _evictionThreshold = 10000;

  /// For `alias({'throttle': ThrottleRequests.factory})`, used as `'throttle:60,1'`.
  static ThrottleRequests Function(List<String> params) get factory =>
      (params) => ThrottleRequests(
        maxAttempts: params.isNotEmpty ? int.parse(params[0]) : 60,
        decayMinutes: params.length > 1 ? int.parse(params[1]) : 1,
      );

  @override
  FutureOr<Response> handle(Request request, Next next) async {
    final key = '${request.ip}|${request.route?.uri ?? request.path}';
    final now = _now();
    final decay = Duration(minutes: decayMinutes);
    var window = _windows[key];
    if (window == null || now.difference(window.start) >= decay) {
      if (window == null && _windows.length >= _evictionThreshold) {
        _windows.removeWhere((_, w) => now.difference(w.start) >= decay);
      }
      window = _Window(now);
      _windows[key] = window;
    }
    window.hits++;
    final remaining = maxAttempts - window.hits;
    if (remaining < 0) {
      final retryAfter =
          decay.inSeconds - now.difference(window.start).inSeconds;
      throw TooManyRequestsHttpException('Too Many Attempts.', {
        'retry-after': '$retryAfter',
        'x-ratelimit-limit': '$maxAttempts',
        'x-ratelimit-remaining': '0',
      });
    }
    final response = await next(request);
    return response.withHeaders({
      'x-ratelimit-limit': '$maxAttempts',
      'x-ratelimit-remaining': '$remaining',
    });
  }
}

class _Window {
  _Window(this.start);
  final DateTime start;
  int hits = 0;
}
