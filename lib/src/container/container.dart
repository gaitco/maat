/// Thrown when [Container.make] is asked for a type nothing was bound to.
class BindingResolutionException implements Exception {
  BindingResolutionException(this.type);
  final Type type;

  @override
  String toString() =>
      'BindingResolutionException: no binding registered for [$type]. '
      'Bind it in a service provider with bind<$type>(...) or singleton<$type>(...).';
}

/// A minimal IoC container keyed by type. No autowiring (Dart AOT has no reflection).
class Container {
  final Map<Type, Object Function(Container)> _factories = {};
  final Map<Type, Object> _instances = {};
  final Set<Type> _shared = {};

  /// Register a factory that runs on every [make].
  void bind<T extends Object>(T Function(Container container) factory) {
    _factories[T] = factory;
    _shared.remove(T);
    _instances.remove(T);
  }

  /// Register a factory whose first result is reused for every later [make].
  void singleton<T extends Object>(T Function(Container container) factory) {
    bind<T>(factory);
    _shared.add(T);
  }

  /// Register an already-built object as the shared instance for [T].
  void instance<T extends Object>(T value) {
    _factories.remove(T);
    _instances[T] = value;
    _shared.add(T);
  }

  /// Resolve [T]. Throws [BindingResolutionException] when unbound.
  T make<T extends Object>() {
    final existing = _instances[T];
    if (existing != null) return existing as T;
    final factory = _factories[T];
    if (factory == null) throw BindingResolutionException(T);
    final value = factory(this) as T;
    if (_shared.contains(T)) _instances[T] = value;
    return value;
  }

  bool has<T extends Object>() =>
      _instances.containsKey(T) || _factories.containsKey(T);
}
