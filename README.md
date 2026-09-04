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
dart pub global activate ptah
maat new blog
```

## Packages

Every package is published on pub.dev and usable on its own.

### Framework

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/maat.svg" width="40" alt=""> | **[maat](https://pub.dev/packages/maat)** | The HTTP framework: routing, middleware, validation, workers, graceful shutdown. |
| <img src="assets/icons/ptah.svg" width="40" alt=""> | **[ptah](https://pub.dev/packages/ptah)** | Installer. `maat new blog` scaffolds a project. |

### Database

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/seshat.svg" width="40" alt=""> | **[seshat](https://pub.dev/packages/seshat)** | The ORM: query builder, typed models, relationships, migrations. |
| <img src="assets/icons/seshat_maat.svg" width="40" alt=""> | **[seshat_maat](https://pub.dev/packages/seshat_maat)** | Wires Seshat into a Maat application. |
| <img src="assets/icons/seshat_mysql.svg" width="40" alt=""> | **[seshat_mysql](https://pub.dev/packages/seshat_mysql)** | MySQL adapter for Seshat. |

### Views

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/khnum.svg" width="40" alt=""> | **[khnum](https://pub.dev/packages/khnum)** | HTML templates with layouts, includes, components, and safe escaping. |
| <img src="assets/icons/khnum_maat.svg" width="40" alt=""> | **[khnum_maat](https://pub.dev/packages/khnum_maat)** | Wires Khnum into a Maat application, with Tailwind commands. |

### Authentication

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/cartouche.svg" width="40" alt=""> | **[cartouche](https://pub.dev/packages/cartouche)** | Personal access tokens for API authentication. |
| <img src="assets/icons/anubis.svg" width="40" alt=""> | **[anubis](https://pub.dev/packages/anubis)** | Database web sessions, CSRF protection, and web authentication. |

### Messaging

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/amarna.svg" width="40" alt=""> | **[amarna](https://pub.dev/packages/amarna)** | Mailables and SMTP delivery. |
| <img src="assets/icons/sistrum.svg" width="40" alt=""> | **[sistrum](https://pub.dev/packages/sistrum)** | Multi-channel notifications: mail and database. |
| <img src="assets/icons/thoth.svg" width="40" alt=""> | **[thoth_realtime](https://pub.dev/packages/thoth_realtime)** | Self-hosted Pusher-protocol WebSocket server. |

### Clients and tooling

| | Package | |
| --- | --- | --- |
| <img src="assets/icons/horus_client.svg" width="40" alt=""> | **[horus_client](https://pub.dev/packages/horus_client)** | Typed HTTP and realtime client runtime for Dart and Flutter. |
| <img src="assets/icons/djed_dev.svg" width="40" alt=""> | **[djed_dev](https://pub.dev/packages/djed_dev)** | Local environment: `*.test` domains, trusted HTTPS, on-demand app processes. |

See the [Maat documentation](https://maat.gaitco.com) for the complete guide.
