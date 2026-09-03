import '../http/request.dart';

/// Anything that can be authenticated — an application's `User` model.
///
/// The framework defines no user class: the columns are the
/// application's business, and a framework that owned them would have to
/// guess at every one of them.
abstract interface class Authenticatable {
  /// The primary key, as written into a token row.
  Object get authIdentifier;

  /// The stored password hash, or `''` for an account that cannot sign
  /// in with a password at all.
  String get authPassword;
}

/// Answers one question: who is making this request?
abstract interface class Guard {
  /// The user for [request], or null when it is not authenticated.
  ///
  /// Called at most once per request — [Authenticate] caches the result
  /// on the request — so an implementation may query the database
  /// without guarding against repeats.
  Future<Authenticatable?> user(Request request);
}
