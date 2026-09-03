import 'dart:async';

import '../config/config.dart';
import '../http/exceptions.dart';
import '../http/middleware/middleware.dart';
import '../http/request.dart';
import '../http/response.dart';
import 'auth.dart';

/// `auth:<guard>` — rejects a request no guard authenticates.
///
/// Registered as an alias with a factory, so the guard travels in the
/// alias string exactly as Laravel writes it:
///
/// ```dart
/// middleware.alias({'auth': Authenticate.factory});
/// Route.middleware(['auth:cartouche']).group(...);
/// ```
class Authenticate extends Middleware {
  Authenticate([this.guard]);

  /// Null uses `config('auth.defaults.guard')`.
  final String? guard;

  static Middleware Function(List<String> params) get factory =>
      (params) => Authenticate(params.isEmpty ? null : params.first);

  @override
  FutureOr<Response> handle(Request request, Next next) async {
    final name =
        guard ?? (config('auth.defaults.guard') as String?) ?? 'cartouche';
    final user = await Auth.guard(name).user(request);
    if (user == null) throw UnauthorizedHttpException('Unauthenticated.');
    request.attributes[authUserAttribute] = user;
    request.attributes[authResolvedAttribute] = true;
    return next(request);
  }
}
