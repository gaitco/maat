import 'dart:async';

import '../request.dart';
import '../response.dart';
import 'middleware.dart';

/// Trims every string in the request input, recursively.
class TrimStrings extends Middleware {
  @override
  FutureOr<Response> handle(Request request, Next next) {
    final data = Map<String, dynamic>.from(request.all());
    request.replace(_clean(data) as Map<String, dynamic>);
    return next(request);
  }

  Object? _clean(Object? value) {
    if (value is String) return value.trim();
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries) e.key as String: _clean(e.value),
      };
    }
    if (value is List) return value.map(_clean).toList();
    return value;
  }
}
