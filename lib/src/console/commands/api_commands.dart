import 'dart:io';

import '../../api/api_document.dart';
import '../../api/dart_client_writer.dart';
import '../../api/openapi_writer.dart';
import '../../config/config.dart';
import '../../routing/router.dart';
import '../command.dart';
import '../generator_command.dart';

/// Builds the document both API commands render, so a spec and the client
/// generated from it always describe the same routes and read the same
/// `config('api.*')` metadata.
mixin BuildsApiDocument on Command {
  ApiDocument buildDocument() {
    final config = app.config;
    return ApiDocument.fromRouter(
      app.make<Router>(),
      info: ApiInfo(
        title: '${config.get('api.title') ?? config.get('app.name') ?? 'API'}',
        version: '${config.get('api.version') ?? '0.1.0'}',
        description: config.get('api.description') as String?,
      ),
      servers: _servers(config),
    );
  }

  /// `config('api.servers')` accepts a bare URL or a `{url, description}` map,
  /// because most applications have exactly one server and should not have to
  /// write a map to say so.
  static List<ApiServer> _servers(Config config) {
    final configured = config.get('api.servers');
    if (configured is! List) return const [];
    return [
      for (final entry in configured)
        if (entry is String)
          ApiServer(entry)
        else if (entry is Map)
          ApiServer(
            '${entry['url']}',
            description: entry['description'] as String?,
          ),
    ];
  }

  /// An empty document is nearly always a forgotten contract rather than an
  /// API with no routes, so it fails instead of writing a valid, useless file.
  bool reportIfEmpty(ApiDocument document) {
    if (document.operations.isNotEmpty) return false;
    error(
      'No route declares an API contract, so there is nothing to generate.\n'
      'Describe a route with .summary(), .body(), .query() or .responds() '
      'and run this again.',
    );
    return true;
  }
}

/// Writes the OpenAPI 3.1 description of the application's route contracts.
class ApiOpenApiCommand extends Command with BuildsApiDocument {
  @override
  String get name => 'api:openapi';
  @override
  String get description => 'Export the API as an OpenAPI 3.1 document';
  @override
  String get signature => '{--output=openapi.json}';

  @override
  Future<int> handle() async {
    final document = buildDocument();
    if (reportIfEmpty(document)) return 1;
    final json = OpenApiWriter(document).toPrettyJson();
    final target = option('output')!;
    // `-` writes to stdout so CI can diff the document without a temp file.
    if (target == '-') {
      out.write(json);
      return 0;
    }
    final file = File(app.path(target));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(json);
    info(
      'Wrote $target — ${document.operations.length} operations, '
      '${document.schemas.length} schemas.',
    );
    return 0;
  }
}

/// Writes a typed Dart client for the same contracts, on `horus_client`.
class ApiClientCommand extends Command with BuildsApiDocument, GeneratesFiles {
  @override
  String get name => 'api:client';
  @override
  String get description => 'Generate a typed Dart client for the API';
  @override
  String get signature => '{--output=lib/api/api_client.dart} {--class=}';

  @override
  Future<int> handle() async {
    final document = buildDocument();
    if (reportIfEmpty(document)) return 1;
    final target = option('output')!;
    final source = DartClientWriter(
      document,
      className: option('class') ?? 'ApiClient',
    ).toSource();
    // Written through the shared generator path, so what lands in the
    // repository is already `dart format` clean.
    writeGenerated(target, source);
    info('Wrote $target — ${document.operations.length} methods.');
    return 0;
  }
}
