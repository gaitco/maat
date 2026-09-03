# Maat Framework

<p align="center"><img src="assets/icon.svg" width="96" alt="Maat icon"></p>

Maat is a full-stack backend framework for Dart with routing, middleware,
validation, authentication, console commands, bounded and streaming request
bodies, multi-isolate workers, and graceful shutdown.

```dart
import 'package:maat/maat.dart';

Route.get('/health', (Request request) => {'status': 'ok'});
await app.serve();
```

Create a project with Ptah:

```bash
dart pub global activate maat_ptah
maat new blog
```

