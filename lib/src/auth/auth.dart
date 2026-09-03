import '../http/exceptions.dart';
import '../http/request.dart';
import 'authenticatable.dart';

/// Where [Authenticate] stores the user it resolved. Namespaced, so a
/// route-model binding named `user` cannot collide with it.
const authUserAttribute = 'auth:user';

/// Marks a request whose guard has already run, so a guard that returned
/// null is not re-run on every access.
const authResolvedAttribute = 'auth:resolved';

/// The guard registry. Laravel's `Auth` facade, minus the parts that
/// need sessions.
abstract final class Auth {
  static final Map<String, Guard Function()> _guards = {};

  /// Registers a guard under [name]. Called from a service provider;
  /// `maat` itself ships none.
  static void extend(String name, Guard Function() factory) =>
      _guards[name] = factory;

  /// The guard registered as [name].
  ///
  /// Throws rather than returning null: an unknown name comes from a typo
  /// in `auth:sanctm`, and the one outcome that must never follow is an
  /// unprotected route.
  static Guard guard(String name) {
    final factory = _guards[name];
    if (factory == null) {
      throw ArgumentError.value(
        name,
        'guard',
        'Unknown authentication guard. Registered: '
            '${_guards.keys.isEmpty ? '(none)' : _guards.keys.join(', ')}.',
      );
    }
    return factory();
  }

  static bool has(String name) => _guards.containsKey(name);

  /// Forgets every guard. Tests only — a registry that survives between
  /// them authenticates one test with another's guard.
  static void reset() => _guards.clear();
}

/// Typed access to the authenticated user.
extension AuthenticatedRequest on Request {
  /// The authenticated user, or null.
  ///
  /// [T] is checked rather than cast away: a route expecting `User` that
  /// receives something else is a wiring mistake, and an error naming
  /// both types finds it faster than a null that reads as "not logged
  /// in".
  ///
  /// A [StateError] rather than a [TypeError], because Dart's `TypeError`
  /// carries no message and the whole value here is saying *which* two
  /// types disagreed.
  T? user<T extends Authenticatable>() {
    final found = attributes[authUserAttribute];
    if (found == null) return null;
    if (found is! T) {
      throw StateError(
        'The authenticated user is a ${found.runtimeType}, not a $T. '
        'Check which guard this route uses against the type it asked for.',
      );
    }
    return found;
  }

  /// The authenticated user, or [UnauthorizedHttpException].
  ///
  /// For handlers behind `auth:` middleware, where null cannot happen and
  /// asserting it once beats a `!` on every line.
  T requireUser<T extends Authenticatable>() =>
      user<T>() ?? (throw UnauthorizedHttpException('Unauthenticated.'));
}
