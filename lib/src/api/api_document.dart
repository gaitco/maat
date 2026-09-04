import '../http/middleware/middleware.dart';
import '../routing/route_definition.dart';
import '../routing/router.dart';
import '../support/str.dart';
import 'rule_schema.dart';
import 'route_contract.dart';
import 'schema.dart';

/// Document-level metadata, Laravel-style: read from `config('api.*')`.
class ApiInfo {
  const ApiInfo({required this.title, required this.version, this.description});

  final String title;
  final String version;
  final String? description;
}

class ApiServer {
  const ApiServer(this.url, {this.description});

  final String url;
  final String? description;
}

/// One path or query parameter.
class ApiParameter {
  const ApiParameter({
    required this.name,
    required this.location,
    required this.schema,
    required this.required,
  });

  final String name;

  /// `path` or `query`.
  final String location;
  final ApiSchema schema;
  final bool required;
}

class ApiSecurityRequirement {
  const ApiSecurityRequirement(this.scheme, this.abilities);

  final String scheme;

  /// Cartouche abilities required by the route.
  ///
  /// These are not OAuth scopes: OpenAPI requires the security-requirement
  /// array for an HTTP bearer scheme to stay empty. The writer exposes them
  /// separately as `x-maat-abilities`.
  final List<String> abilities;
}

/// One verb on one path: everything both renderers need about a single call.
class ApiOperation {
  ApiOperation({
    required this.method,
    required this.path,
    required this.operationId,
    required this.parameters,
    required this.responses,
    required this.security,
    this.summary,
    this.description,
    this.tags = const [],
    this.requestBody,
    this.deprecated = false,
  });

  final String method;
  final String path;
  final String operationId;
  final String? summary;
  final String? description;
  final List<String> tags;
  final List<ApiParameter> parameters;
  final ApiSchema? requestBody;
  final List<ApiResponse> responses;
  final List<ApiSecurityRequirement> security;
  final bool deprecated;

  Iterable<ApiParameter> get pathParameters =>
      parameters.where((p) => p.location == 'path');
  Iterable<ApiParameter> get queryParameters =>
      parameters.where((p) => p.location == 'query');

  /// The response a client gets on success, or null when there is no body.
  ApiResponse? get successResponse {
    for (final response in responses) {
      if (response.status >= 200 &&
          response.status < 300 &&
          response.schema.type != ApiType.none) {
        return response;
      }
    }
    return null;
  }
}

/// Every documented operation plus the schemas they share.
///
/// Both renderers read this, so the OpenAPI document and the generated Dart
/// client are two views of one description and cannot drift apart.
class ApiDocument {
  ApiDocument({
    required this.info,
    required this.servers,
    required this.operations,
    required this.schemas,
  });

  final ApiInfo info;
  final List<ApiServer> servers;

  /// In route registration order, which reads like the routes file.
  final List<ApiOperation> operations;

  /// Named object schemas, sorted by name.
  final Map<String, ApiSchema> schemas;

  bool get usesBearerAuth =>
      operations.any((operation) => operation.security.isNotEmpty);

  /// Collects every route carrying a [RouteContract].
  ///
  /// A route without one is skipped: the contract is the opt-in, which keeps
  /// HTML routes out of the API document without guessing from a prefix.
  factory ApiDocument.fromRouter(
    Router router, {
    required ApiInfo info,
    List<ApiServer> servers = const [],
  }) {
    final operations = <ApiOperation>[];
    final ids = <String, String>{};
    final endpoints = <String, String>{};
    for (final route in router.routes) {
      final contract = route.contract;
      if (contract == null) continue;
      final verbs = route.methods.where(_documented).toList();
      if (verbs.isEmpty) {
        throw StateError(
          'Route [${route.methods.join('|')} ${route.uri}] declares an API '
          'contract, but HEAD and OPTIONS are never documented — every '
          'OpenAPI consumer derives them. Give the route a verb clients call, '
          'or drop the contract.',
        );
      }
      for (var i = 0; i < verbs.length; i++) {
        final operation = _operationFor(route, contract, verbs[i], i);
        final endpoint = '${operation.method} ${operation.path}';
        final duplicate = endpoints[endpoint];
        if (duplicate != null) {
          throw StateError(
            'Two contracted routes describe [$endpoint]: [$duplicate] and '
            '[${operation.operationId}]. Only the first route can handle the '
            'request, so the API document cannot describe both.',
          );
        }
        final clash = ids[operation.operationId];
        if (clash != null) {
          throw StateError(
            'Two operations are both called [${operation.operationId}]: '
            '$clash and ${operation.method} ${operation.path}. Give one of '
            'them an explicit id with `.operation(...)`, or the generated '
            'client would declare the same method twice.',
          );
        }
        endpoints[endpoint] = operation.operationId;
        ids[operation.operationId] = endpoint;
        operations.add(operation);
      }
    }
    final schemas = <String, ApiSchema>{};
    for (final operation in operations) {
      operation.requestBody?.collectNamed(schemas);
      for (final response in operation.responses) {
        response.schema.collectNamed(schemas);
      }
    }
    return ApiDocument(
      info: info,
      servers: servers,
      operations: operations,
      schemas: Map.fromEntries(
        schemas.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
  }

  /// HEAD is derived from GET by every OpenAPI consumer, and OPTIONS is
  /// transport rather than API surface. Documenting either would produce
  /// duplicate client methods for calls nobody writes by hand.
  static bool _documented(String method) =>
      method != 'HEAD' && method != 'OPTIONS';

  static ApiOperation _operationFor(
    RouteDefinition route,
    RouteContract contract,
    String method,
    int verbIndex,
  ) {
    final path = route.uri.replaceAll('?}', '}');
    final security = _securityFor(route);
    final body = contract.bodySchema(
      '${Str.studly(_baseId(route, method))}Request',
    );
    return ApiOperation(
      method: method,
      path: path,
      operationId: _operationId(route, contract, method, verbIndex),
      summary: contract.summary,
      description: contract.description,
      tags: List.unmodifiable(contract.tags),
      parameters: _parametersFor(route, contract),
      requestBody: body,
      responses: _responsesFor(contract, security.isNotEmpty),
      security: security,
      deprecated: contract.deprecated,
    );
  }

  static List<ApiParameter> _parametersFor(
    RouteDefinition route,
    RouteContract contract,
  ) {
    final parameters = <ApiParameter>[];
    for (final name in route.paramNames) {
      final rules = contract.pathRules[name];
      // A path parameter is always required: OpenAPI has no way to say
      // otherwise, and an untyped one is a string, which is what the URL
      // actually carries.
      parameters.add(
        ApiParameter(
          name: name,
          location: 'path',
          schema: rules == null
              ? const ApiSchema.string()
              : rulesToSchema({name: rules}).properties![name]!.bare,
          required: true,
        ),
      );
    }
    final query = rulesToSchema(contract.queryRules);
    for (final entry
        in query.properties?.entries ?? const <MapEntry<String, ApiSchema>>[]) {
      parameters.add(
        ApiParameter(
          name: entry.key,
          location: 'query',
          schema: entry.value,
          required: !entry.value.isOptional,
        ),
      );
    }
    return parameters;
  }

  static List<ApiResponse> _responsesFor(RouteContract contract, bool secured) {
    final responses = {...contract.responses};
    if (!responses.keys.any((status) => status >= 200 && status < 300)) {
      // OpenAPI requires at least one response. A contract that only adds a
      // summary or input rules still has an unknown successful result, which
      // is represented honestly as Object? rather than invented from the
      // handler's Object? return type.
      responses[200] = const ApiResponse(200, ApiSchema.any());
    }
    // Errors Maat renders itself. Documenting them is what makes a generated
    // client's failure cases match what the server will really send.
    if (secured) {
      responses.putIfAbsent(
        401,
        () => const ApiResponse(
          401,
          apiErrorSchema,
          description: 'Unauthenticated.',
        ),
      );
    }
    if (contract.hasInput) {
      responses.putIfAbsent(
        422,
        () => const ApiResponse(
          422,
          apiValidationErrorSchema,
          description: 'The given data was invalid.',
        ),
      );
    }
    return responses.values.toList()
      ..sort((a, b) => a.status.compareTo(b.status));
  }

  /// Cartouche's aliases: `auth`, `auth:guard`, `ability:name`,
  /// `abilities:a,b`. Only string middleware is read — an instance carries no
  /// declarative name to document.
  static List<ApiSecurityRequirement> _securityFor(RouteDefinition route) {
    var secured = false;
    final abilities = <String>[];
    for (final entry in route.middlewareList) {
      if (entry is! String) continue;
      final (:name, :params) = parseMiddlewareAlias(entry);
      if (name == 'auth') secured = true;
      if (name == 'ability' || name == 'abilities') abilities.addAll(params);
    }
    if (!secured && abilities.isEmpty) return const [];
    return [ApiSecurityRequirement(apiBearerScheme, abilities..sort())];
  }

  static String _operationId(
    RouteDefinition route,
    RouteContract contract,
    String method,
    int verbIndex,
  ) {
    final explicit = contract.operationId;
    if (explicit != null) {
      return verbIndex == 0
          ? explicit
          : '$explicit${Str.studly(method.toLowerCase())}';
    }
    final base = Str.camel(_baseId(route, method));
    // `Route.resource` registers update as PUT and PATCH on one route, so the
    // second verb needs its own name or the client would declare the method
    // twice.
    return verbIndex == 0 ? base : '$base${Str.studly(method.toLowerCase())}';
  }

  static String _baseId(RouteDefinition route, String method) {
    final name = route.routeName;
    if (name != null) return name.replaceAll('.', '_');
    final segments = route.uri
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) => segment.startsWith('{')
              ? 'by_${segment.replaceAll(RegExp(r'[{}?]'), '')}'
              : segment,
        );
    return [method.toLowerCase(), ...segments].join('_');
  }
}

/// The security scheme name used for Maat's bearer tokens.
const apiBearerScheme = 'bearerAuth';

/// `{"message": "..."}` — what `ExceptionHandler` renders for an HTTP error.
const apiErrorSchema = ApiSchema.object({
  'message': ApiSchema.string(),
}, name: 'ErrorResponse');

/// `{"message": "...", "errors": {"field": ["..."]}}` — Maat's 422 body.
const apiValidationErrorSchema = ApiSchema.object({
  'message': ApiSchema.string(),
  // Field name to messages. Left free-form: the keys are whatever the
  // request sent, so there is no fixed shape to declare.
  'errors': ApiSchema.object({}),
}, name: 'ValidationError');
