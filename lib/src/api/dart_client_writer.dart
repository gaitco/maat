import 'dart:convert';

import '../support/str.dart';
import 'api_document.dart';
import 'schema.dart';

/// Generates a null-safe Dart client for an [ApiDocument], on top of the
/// `horus_client` runtime.
///
/// The emitted file has the shape `horus_client`'s own example documents: one
/// `Endpoint` constant per operation and one thin class whose methods hand
/// those to [HorusClient.send]. Transport, retries and error mapping stay in
/// the runtime, so this only has to get the types right.
///
/// Every parameter is named — path, query and body alike — so adding a query
/// parameter later can never silently reorder an existing call.
class DartClientWriter {
  const DartClientWriter(this.document, {this.className = 'ApiClient'});

  final ApiDocument document;
  final String className;

  /// Dart's reserved words that could plausibly be an API field name. A
  /// clashing name gets a trailing underscore rather than being dropped.
  static const _reserved = {
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  String toSource() {
    _validateNames();
    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('//')
      ..writeln('// Generated from this application\'s route contracts by')
      ..writeln('// `sesh api:client`. Edit the contracts, not this file.')
      ..writeln()
      ..writeln("import 'package:horus_client/horus_client.dart';")
      ..writeln();

    for (final schema in _dtos().values) {
      _writeDto(buffer, schema);
    }
    for (final operation in document.operations) {
      _writeEndpoint(buffer, operation);
    }
    _writeClient(buffer);
    return buffer.toString();
  }

  /// Only schemas a client actually decodes or sends: request bodies and
  /// successful responses. Error bodies surface as [HorusClientException],
  /// so generating classes for them would be dead code.
  Map<String, ApiSchema> _dtos() {
    final named = <String, ApiSchema>{};
    for (final operation in document.operations) {
      operation.requestBody?.collectNamed(named);
      operation.successResponse?.schema.collectNamed(named);
    }
    return Map.fromEntries(
      named.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  void _writeDto(StringBuffer buffer, ApiSchema schema) {
    final name = _dtoName(schema.name!);
    final fields = schema.properties!;
    if (schema.description != null) {
      _writeDocs(buffer, schema.description!);
    }
    buffer
      ..writeln('final class $name {')
      ..writeln('  const $name({');
    for (final entry in fields.entries) {
      final required = entry.value.isDartNullable ? '' : 'required ';
      buffer.writeln('    ${required}this.${_identifier(entry.key)},');
    }
    buffer
      ..writeln('  });')
      ..writeln()
      ..writeln(
        '  factory $name.fromJson(Map<String, Object?> json) => $name(',
      );
    for (final entry in fields.entries) {
      buffer.writeln(
        '    ${_identifier(entry.key)}: '
        '${_decode(entry.value, 'json[${_literal(entry.key)}]')},',
      );
    }
    buffer
      ..writeln('  );')
      ..writeln();
    for (final entry in fields.entries) {
      buffer.writeln(
        '  final ${_dartType(entry.value)} ${_identifier(entry.key)};',
      );
    }
    buffer
      ..writeln()
      ..writeln('  Map<String, Object?> toJson() => {');
    for (final entry in fields.entries) {
      final identifier = _identifier(entry.key);
      // An optional key is left out entirely when it is null: that is the
      // difference `sometimes` makes on the server, and sending an explicit
      // null instead would fail a `required` rule the client never broke.
      final guard = entry.value.isOptional ? 'if ($identifier != null) ' : '';
      buffer.writeln(
        '    $guard${_literal(entry.key)}: '
        '${_encode(entry.value, identifier)},',
      );
    }
    buffer
      ..writeln('  };')
      ..writeln('}')
      ..writeln();
  }

  void _writeEndpoint(StringBuffer buffer, ApiOperation operation) {
    final response = operation.successResponse?.schema;
    final type = response == null ? 'void' : _dartType(response);
    buffer
      ..writeln('final _${operation.operationId} = Endpoint<$type>(')
      ..writeln('  method: ${_literal(operation.method)},')
      ..writeln('  path: ${_literal(operation.path)},')
      ..writeln(
        response == null
            ? '  decode: (json) {},'
            : '  decode: (json) => ${_decode(response, 'json')},',
      )
      ..writeln(');')
      ..writeln();
  }

  void _writeClient(StringBuffer buffer) {
    final title = document.info.title;
    _writeDocs(buffer, 'A typed client for $title ${document.info.version}.');
    buffer
      ..writeln('final class $className {')
      ..writeln('  const $className(this._client);')
      ..writeln()
      ..writeln('  final HorusClient _client;')
      ..writeln();
    for (final operation in document.operations) {
      _writeMethod(buffer, operation);
    }
    buffer.writeln('}');
  }

  void _writeMethod(StringBuffer buffer, ApiOperation operation) {
    final response = operation.successResponse?.schema;
    final returns = response == null ? 'void' : _dartType(response);
    final parameters = <String>[
      for (final parameter in operation.pathParameters)
        'required ${_dartType(parameter.schema)} ${_identifier(parameter.name)}',
      if (operation.requestBody != null)
        'required ${_dtoName(operation.requestBody!.name!)} body',
      for (final parameter in operation.queryParameters)
        parameter.required
            ? 'required ${_dartType(parameter.schema)} '
                  '${_identifier(parameter.name)}'
            : '${_optional(parameter.schema)} ${_identifier(parameter.name)}',
    ];
    final arguments = <String>[
      '_${operation.operationId}',
      if (operation.pathParameters.isNotEmpty)
        'pathParameters: {${[for (final parameter in operation.pathParameters) '${_literal(parameter.name)}: '
              '${_encode(parameter.schema, _identifier(parameter.name))}'].join(', ')}}',
      if (operation.queryParameters.isNotEmpty)
        'queryParameters: {${[for (final parameter in operation.queryParameters) '${_literal(parameter.name)}: '
              '${_encode(parameter.schema, _identifier(parameter.name))}'].join(', ')}}',
      if (operation.requestBody != null) 'body: body.toJson()',
    ];

    for (final line in _documentation(operation)) {
      _writeDocs(buffer, line, indent: '  ');
    }
    if (operation.deprecated) {
      buffer.writeln("  @Deprecated('This operation is deprecated.')");
    }
    buffer
      ..writeln(
        '  Future<$returns> ${operation.operationId}('
        '${parameters.isEmpty ? '' : '{${parameters.join(', ')}}'}) =>',
      )
      ..writeln('      _client.send(${arguments.join(', ')});')
      ..writeln();
  }

  List<String> _documentation(ApiOperation operation) => [
    if (operation.summary != null) operation.summary!,
    if (operation.summary != null && operation.description != null) '',
    if (operation.description != null) operation.description!,
    if (operation.summary != null || operation.description != null) '',
    '`${operation.method} ${operation.path}`'
        '${operation.security.isEmpty ? '' : ' — requires a bearer token'}'
        '${operation.security.expand((s) => s.abilities).isEmpty ? '' : ' with '
                  '${operation.security.expand((s) => s.abilities).join(', ')}'}.',
  ];

  void _validateNames() {
    _requireIdentifier(className, 'client class', startsUppercase: true);

    final dtoNames = <String, String>{};
    for (final schema in _dtos().values) {
      final dto = _dtoName(schema.name!);
      _requireIdentifier(
        dto,
        'DTO for schema [${schema.name}]',
        startsUppercase: true,
      );
      final existing = dtoNames[dto];
      if (existing != null && existing != schema.name) {
        throw StateError(
          'Schemas [$existing] and [${schema.name}] both generate the Dart '
          'type [$dto]. Rename one schema.',
        );
      }
      dtoNames[dto] = schema.name!;

      final fields = <String, String>{};
      for (final wireName in schema.properties!.keys) {
        final identifier = _identifier(wireName);
        _requireIdentifier(
          identifier,
          'field [$wireName] in schema [${schema.name}]',
        );
        final clash = fields[identifier];
        if (clash != null && clash != wireName) {
          throw StateError(
            'Fields [$clash] and [$wireName] in schema [${schema.name}] both '
            'generate the Dart field [$identifier]. Rename one field.',
          );
        }
        fields[identifier] = wireName;
      }
    }

    for (final operation in document.operations) {
      _requireIdentifier(operation.operationId, 'operation id');
      final parameters = <String, String>{};
      if (operation.requestBody != null) parameters['body'] = 'request body';
      for (final parameter in operation.parameters) {
        final identifier = _identifier(parameter.name);
        _requireIdentifier(identifier, 'parameter [${parameter.name}]');
        final clash = parameters[identifier];
        if (clash != null) {
          throw StateError(
            'Operation [${operation.operationId}] maps both $clash and '
            '[${parameter.name}] to the Dart parameter [$identifier]. '
            'Rename one parameter.',
          );
        }
        parameters[identifier] = parameter.name;
      }
    }
  }

  static void _requireIdentifier(
    String value,
    String role, {
    bool startsUppercase = false,
  }) {
    final pattern = startsUppercase
        ? RegExp(r'^[A-Z][A-Za-z0-9]*$')
        : RegExp(r'^[a-z][A-Za-z0-9_]*$');
    if (!pattern.hasMatch(value) || _reserved.contains(value)) {
      throw StateError(
        'The $role [$value] is not a valid public Dart identifier. Use a '
        '${startsUppercase ? 'PascalCase name' : 'lowerCamelCase name'}.',
      );
    }
  }

  static void _writeDocs(
    StringBuffer buffer,
    String text, {
    String indent = '',
  }) {
    for (final line
        in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      buffer.writeln('$indent/// $line');
    }
  }

  static String _literal(String value) {
    final encoded = jsonEncode(value).replaceAll(r'$', r'\$');
    if (value.contains("'")) return encoded;
    return "'${encoded.substring(1, encoded.length - 1).replaceAll(r'\"', '"')}'";
  }

  /// A query parameter's type, always nullable: omitting it is how a caller
  /// says "do not send this one".
  String _optional(ApiSchema schema) {
    final type = _dartType(schema);
    return type.endsWith('?') || type == 'Object?' ? type : '$type?';
  }

  String _dtoName(String schemaName) => '${Str.studly(schemaName)}Dto';

  String _dartType(ApiSchema schema) {
    final base = switch (schema.type) {
      ApiType.string => schema.format == 'date-time' ? 'DateTime' : 'String',
      ApiType.integer => 'int',
      // `num`, not `double`: JSON gives back an int for a whole number, and
      // a `double` cast on one throws.
      ApiType.number => 'num',
      ApiType.boolean => 'bool',
      ApiType.array => 'List<${_dartType(schema.items!)}>',
      ApiType.object =>
        schema.name == null ? 'Map<String, Object?>' : _dtoName(schema.name!),
      ApiType.any => 'Object?',
      ApiType.none => 'void',
    };
    return schema.isDartNullable && base != 'Object?' ? '$base?' : base;
  }

  /// JSON expression [expr] to a value of the schema's Dart type.
  String _decode(ApiSchema schema, String expr) {
    if (schema.isDartNullable && schema.type != ApiType.any) {
      return '$expr == null ? null : ${_decode(schema.bare, expr)}';
    }
    return switch (schema.type) {
      ApiType.string when schema.format == 'date-time' =>
        'DateTime.parse($expr! as String)',
      ApiType.string => '$expr! as String',
      ApiType.integer => '$expr! as int',
      ApiType.number => '$expr! as num',
      ApiType.boolean => '$expr! as bool',
      ApiType.array =>
        '[for (final item in $expr! as List<Object?>) '
            '${_decode(schema.items!, 'item')}]',
      ApiType.object when schema.name != null =>
        '${_dtoName(schema.name!)}.fromJson($expr! as Map<String, Object?>)',
      ApiType.object => '$expr! as Map<String, Object?>',
      ApiType.any || ApiType.none => expr,
    };
  }

  /// A Dart expression [expr] back to something `jsonEncode` accepts.
  String _encode(ApiSchema schema, String expr) {
    final access = schema.isDartNullable ? '?.' : '.';
    return switch (schema.type) {
      ApiType.string when schema.format == 'date-time' =>
        '$expr${access}toIso8601String()',
      ApiType.array when _needsEncoding(schema.items!) =>
        '$expr${access}map((item) => '
            '${_encode(schema.items!, 'item')}).toList()',
      ApiType.object when schema.name != null => '$expr${access}toJson()',
      _ => expr,
    };
  }

  static bool _needsEncoding(ApiSchema schema) => switch (schema.type) {
    ApiType.string => schema.format == 'date-time',
    ApiType.array => _needsEncoding(schema.items!),
    ApiType.object => schema.name != null,
    _ => false,
  };

  static String _identifier(String wireName) {
    final camel = Str.camel(wireName);
    return _reserved.contains(camel) ? '${camel}_' : camel;
  }
}
