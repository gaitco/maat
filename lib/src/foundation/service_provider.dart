import 'dart:async';

import 'application.dart';

/// Registers bindings in [register], performs setup in [boot], and releases
/// resources in [shutdown].
/// All providers' [register] run before any [boot], exactly like Laravel.
abstract class ServiceProvider {
  ServiceProvider(this.app);
  final Application app;

  void register() {}

  FutureOr<void> boot() {}

  FutureOr<void> shutdown() {}
}
