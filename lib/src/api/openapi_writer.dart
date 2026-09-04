import 'dart:convert';

import 'api_document.dart';
import 'route_contract.dart';
import 'schema.dart';

/// Renders an [ApiDocument] as an OpenAPI 3.1 document.
///
/// The output is byte-stable: paths are sorted, verbs follow OpenAPI's own
/// order, schemas are sorted by name, and every map is built in a fixed
/// insertion order. Nothing reads the clock, the filesystem, or a hash set.
/// A `sesh api:openapi && git diff --exit-code` in CI is therefore a real
/// check rather than a source of noise.
class OpenApiWriter {
  const OpenApiWriter(this.document);

  final ApiDocument document;

  /// OpenAPI's own ordering for the verbs inside a path item.
  static const _verbOrder = [
    'GET',
    'PUT',
    'POST',
    'DELETE',
    'OPTIONS',
    'HEAD',
    'PATCH',
    'TRACE',
  ];

  static const _statusText = {
    200: 'OK',
    201: 'Created',
    202: 'Accepted',
    204: 'No content',
    400: 'Bad request',
    401: 'Unauthenticated.',
    403: 'Forbidden',
    404: 'Not found',
    409: 'Conflict',
    422: 'The given data was invalid.',
    429: 'Too many requests',
    500: 'Server error',
  };

  String toPrettyJson() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  Map<String, Object?> toJson() => {
    'openapi': '3.1.0',
    'info': {
      'title': document.info.title,
      if (document.info.description != null)
        'description': document.info.description,
      'version': document.info.version,
    },
    if (document.servers.isNotEmpty)
      'servers': [
        for (final server in document.servers)
          {
            'url': server.url,
            if (server.description != null) 'description': server.description,
          },
      ],
    'paths': _paths(),
    if (document.schemas.isNotEmpty || document.usesBearerAuth)
      'components': {
        if (document.schemas.isNotEmpty)
          'schemas': {
            for (final entry in document.schemas.entries)
              entry.key: _schema(entry.value, inline: true),
          },
        if (document.usesBearerAuth)
          'securitySchemes': {
            apiBearerScheme: {
              'type': 'http',
              'scheme': 'bearer',
              'description':
                  'A Cartouche personal access token, sent as '
                  '`Authorization: Bearer <token>`.',
            },
          },
      },
  };

  Map<String, Object?> _paths() {
    final byPath = <String, List<ApiOperation>>{};
    for (final operation in document.operations) {
      byPath.putIfAbsent(operation.path, () => []).add(operation);
    }
    final paths = byPath.keys.toList()..sort();
    return {
      for (final path in paths)
        path: {
          for (final operation in byPath[path]!..sort(_byVerb))
            operation.method.toLowerCase(): _operation(operation),
        },
    };
  }

  static int _byVerb(ApiOperation a, ApiOperation b) =>
      _verbOrder.indexOf(a.method).compareTo(_verbOrder.indexOf(b.method));

  Map<String, Object?> _operation(ApiOperation operation) => {
    'operationId': operation.operationId,
    if (operation.tags.isNotEmpty) 'tags': operation.tags,
    if (operation.summary != null) 'summary': operation.summary,
    if (operation.description != null) 'description': operation.description,
    if (operation.deprecated) 'deprecated': true,
    if (operation.parameters.isNotEmpty)
      'parameters': [
        for (final parameter in operation.parameters)
          {
            'name': parameter.name,
            'in': parameter.location,
            'required': parameter.required,
            if (parameter.schema.description != null)
              'description': parameter.schema.description,
            'schema': _schema(parameter.schema),
          },
      ],
    if (operation.requestBody != null)
      'requestBody': {
        'required': true,
        'content': {
          'application/json': {'schema': _schema(operation.requestBody!)},
        },
      },
    'responses': {
      for (final response in operation.responses)
        '${response.status}': _response(response),
    },
    if (operation.security.isNotEmpty)
      'security': [
        for (final requirement in operation.security)
          // OpenAPI permits scopes only for OAuth2 and OpenID Connect.
          // Cartouche abilities remain useful metadata, but an HTTP bearer
          // requirement must carry an empty array.
          {requirement.scheme: const <String>[]},
      ],
    if (operation.security.expand((entry) => entry.abilities).isNotEmpty)
      'x-maat-abilities': [
        for (final ability in operation.security.expand(
          (entry) => entry.abilities,
        ))
          ability,
      ],
  };

  Map<String, Object?> _response(ApiResponse response) => {
    'description':
        response.description ??
        _statusText[response.status] ??
        'Response ${response.status}',
    if (response.schema.type != ApiType.none)
      'content': {
        'application/json': {'schema': _schema(response.schema)},
      },
  };

  /// A named object becomes a `$ref` unless [inline] asks for the definition
  /// itself, which is what `components/schemas` holds.
  Map<String, Object?> _schema(ApiSchema schema, {bool inline = false}) {
    if (!inline && schema.name != null && schema.type == ApiType.object) {
      // A `$ref` cannot carry siblings in 3.0 and only some tools honour them
      // in 3.1, so a nullable reference is expressed as a one-of instead.
      return schema.isNullable
          ? {
              'oneOf': [
                {r'$ref': '#/components/schemas/${schema.name}'},
                {'type': 'null'},
              ],
            }
          : {r'$ref': '#/components/schemas/${schema.name}'};
    }
    if (schema.type == ApiType.any) {
      return {
        if (schema.description != null) 'description': schema.description,
      };
    }
    return {
      ..._type(schema),
      if (schema.description != null) 'description': schema.description,
      if (schema.format != null) 'format': schema.format,
      if (schema.values != null) 'enum': schema.values,
      if (schema.pattern != null) 'pattern': schema.pattern,
      if (schema.minimum != null) 'minimum': schema.minimum,
      if (schema.maximum != null) 'maximum': schema.maximum,
      if (schema.minLength != null) 'minLength': schema.minLength,
      if (schema.maxLength != null) 'maxLength': schema.maxLength,
      if (schema.minItems != null) 'minItems': schema.minItems,
      if (schema.maxItems != null) 'maxItems': schema.maxItems,
      if (schema.items != null) 'items': _schema(schema.items!),
      if (schema.type == ApiType.object) ...{
        'properties': {
          for (final entry in schema.properties!.entries)
            entry.key: _schema(entry.value),
        },
        if (_required(schema).isNotEmpty) 'required': _required(schema),
      },
    };
  }

  /// OpenAPI 3.1 is JSON Schema 2020-12, where nullability is part of the
  /// type — not 3.0's separate `nullable: true`.
  Map<String, Object?> _type(ApiSchema schema) {
    final name = schema.type.name;
    return {
      'type': schema.isNullable ? [name, 'null'] : name,
    };
  }

  static List<String> _required(ApiSchema schema) => [
    for (final entry in schema.properties!.entries)
      if (!entry.value.isOptional) entry.key,
  ];
}
