import 'request.dart';

/// Marks a value that must not appear in the output at all. Laravel calls
/// this `MissingValue`; it is why `when(false, ...)` removes a key rather
/// than setting it to null — absent and null mean different things to a
/// client.
///
/// Deliberately NOT `const`. Dart canonicalises const objects program-wide, so
/// `const Object()` here is the SAME instance as a `const Object()` written
/// anywhere else — and every such value a developer put in a payload would be
/// silently deleted from their response, with no error. A plain `Object()` is a
/// fresh allocation nothing else can name, which is what a sentinel requires.
/// Do not "optimise" this back to `const`.
final Object _missing = Object();

/// Shapes a single [T] into the JSON an endpoint returns, so the model stays
/// free of presentation concerns. Laravel's `JsonResource`.
///
/// ```dart
/// class UserResource extends JsonResource<User> {
///   UserResource(super.resource);
///
///   @override
///   Map<String, Object?> toJson(Request request) => {
///     'id': resource.id,
///     'email': when(request.user.isAdmin, () => resource.email),
///     'posts': whenLoaded('posts'),
///   };
/// }
/// ```
///
/// There is deliberately no `static collection()` here: Laravel writes
/// `UserResource::collection($users)`, but Dart does not inherit statics, so
/// a `collection` declared on this base class would not resolve through
/// `UserResource`. Collections are the top-level `resourceCollection(items,
/// UserResource.new)`, which takes a constructor tear-off. Do not "fix" this
/// by adding a static.
abstract class JsonResource<T> {
  JsonResource(this.resource);

  final T resource;
  Map<String, Object?> _additional = const {};

  /// Shape [resource] for this request. Use [when] and [whenLoaded] for
  /// values that should sometimes be absent.
  Map<String, Object?> toJson(Request request);

  /// Wrap the payload in a top-level `data` key. Laravel's default.
  bool get wrap => true;

  /// Present only when [condition]. [value] is not called otherwise, so
  /// `when(isAdmin, () => expensive())` costs nothing for non-admins.
  Object? when(bool condition, Object? Function() value) =>
      condition ? value() : _missing;

  /// Present only when the relation was eager-loaded. Guards the N+1 a
  /// naive `resource.posts` would cause on a collection.
  ///
  /// Read dynamically: this package must not depend on the ORM, so a
  /// resource over anything that is not a model simply reports the relation
  /// as absent rather than throwing.
  Object? whenLoaded(String relation) {
    final Map<String, Object?>? loaded;
    try {
      loaded = (resource as dynamic).loadedRelations as Map<String, Object?>?;
    } on NoSuchMethodError {
      return _missing;
    }
    if (loaded == null || !loaded.containsKey(relation)) return _missing;
    return loaded[relation];
  }

  /// Whether [value] is the missing-value marker returned by [when] and
  /// [whenLoaded].
  ///
  /// [when] and [whenLoaded] already hand this marker across package
  /// boundaries, so the value is public even though its name is not. Anything
  /// building its own container out of them — `resourceCollection` in
  /// `maat_seshat`, for one — needs to recognise it in order to pass it
  /// through untouched. Without this, callers are forced to reconstruct the
  /// marker by identity, which welds them to today's representation.
  static bool isMissing(Object? value) => identical(value, _missing);

  /// Merge extra top-level keys beside `data`.
  JsonResource<T> additional(Map<String, Object?> extra) {
    _additional = extra;
    return this;
  }

  /// Build the final response map, stripping every missing value.
  ///
  /// [additional] keys go in FIRST so the resource's own payload always wins:
  /// `additional({'data': ...})` must not be able to clobber the body. They
  /// are stripped through the same path as the body, so a nested resource or
  /// a sentinel handed to [additional] cannot reach the JSON encoder raw.
  Map<String, Object?> resolve(Request request) {
    final body = _strip(toJson(request), request) as Map<String, Object?>;
    final extra = _strip(_additional, request) as Map<String, Object?>;
    if (!wrap) return {...extra, ...body};
    return {...extra, 'data': body};
  }

  /// Recurses through maps AND lists: a nested resource that hides a field
  /// would otherwise leak the sentinel into the JSON encoder, which fails at
  /// runtime far from the cause.
  static Object? _strip(Object? value, Request request) {
    if (identical(value, _missing)) return _missing;
    // Inlined unwrapped, as Laravel does — a nested resource contributes its
    // fields, not a second `data` envelope.
    if (value is JsonResource) return _strip(value.toJson(request), request);
    if (value is Map) {
      final out = <String, Object?>{};
      for (final e in value.entries) {
        final v = _strip(e.value, request);
        if (!identical(v, _missing)) out['${e.key}'] = v;
      }
      return out;
    }
    if (value is Iterable) {
      final out = <Object?>[];
      for (final v in value) {
        final stripped = _strip(v, request);
        if (!identical(stripped, _missing)) out.add(stripped);
      }
      return out;
    }
    return value;
  }
}
