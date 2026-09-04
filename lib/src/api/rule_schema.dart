import '../validation/rule.dart';
import 'schema.dart';

/// Builds an [ApiSchema] from a Laravel-style rule map.
///
/// The rules handed to this are the same ones the handler validates with, so
/// the document describes what the server actually enforces rather than a
/// second, hand-written description of it.
///
/// Dotted and wildcard keys nest the way the validator reads them:
/// `author.name` is a property of an object, `tags.*` is an array's items.
ApiSchema rulesToSchema(Map<String, Object> rules, {String? name}) {
  final root = _Node();
  for (final entry in rules.entries) {
    var node = root;
    for (final segment in entry.key.split('.')) {
      node = node.children.putIfAbsent(segment, _Node.new);
    }
    node.rules = entry.value;
  }
  final schema = _schemaFor(root, isRoot: true);
  return name == null || schema.type != ApiType.object
      ? schema
      : schema.named(name);
}

/// One path in the rule map. A node can carry both its own rules and
/// children: `'author' => 'required'` next to `'author.name' => 'string'`.
class _Node {
  Object? rules;
  final Map<String, _Node> children = {};
}

const _formats = {
  'email': 'email',
  'url': 'uri',
  'uuid': 'uuid',
  'date': 'date-time',
};

ApiSchema _schemaFor(
  _Node node, {
  bool isRoot = false,
  bool isArrayItem = false,
}) {
  final parsed = node.rules == null
      ? const <Object>[]
      : parseRuleSet(node.rules!);
  final by = <String, ParsedRule>{
    for (final rule in parsed.whereType<ParsedRule>()) rule.name: rule,
  };

  final items = node.children['*'];
  final ApiSchema base;
  if (items != null) {
    base = ApiSchema.array(
      _schemaFor(items, isArrayItem: true),
      minItems: _sizeBound(by, 'min') ?? _between(by, 0),
      maxItems: _sizeBound(by, 'max') ?? _between(by, 1),
    );
  } else if (node.children.isNotEmpty) {
    base = ApiSchema.object({
      for (final entry in node.children.entries)
        entry.key: _schemaFor(entry.value),
    });
  } else {
    base = _scalarFor(by);
  }

  // The root object is the body itself: it is never "optional", and marking it
  // nullable would say the whole request may be sent as `null`.
  if (isRoot) return base;
  final required =
      !by.containsKey('sometimes') &&
      (by.containsKey('required') ||
          by.containsKey('present') ||
          (!isArrayItem && items == null && _childRequiresPresence(node)));
  return _apply(
    base,
    nullable: by.containsKey('nullable'),
    // An array item already exists by definition. `tags.* => string` means
    // List<String>, while `nullable|string` means List<String?>.
    optional: isArrayItem ? false : !required,
  );
}

ApiSchema _scalarFor(Map<String, ParsedRule> by) {
  final rawValues = by['in']?.params;
  final numeric = by.containsKey('integer') || by.containsKey('numeric');
  if (numeric) {
    final min = _numBound(by, 'min') ?? _numBetween(by, 0);
    final max = _numBound(by, 'max') ?? _numBetween(by, 1);
    return by.containsKey('integer')
        ? ApiSchema.integer(
            minimum: min,
            maximum: max,
            values: _parsedValues(rawValues, int.tryParse),
          )
        : ApiSchema.number(
            minimum: min,
            maximum: max,
            values: _parsedValues(rawValues, num.tryParse),
          );
  }
  if (by.containsKey('boolean')) {
    return ApiSchema.boolean(values: _booleanValues(rawValues));
  }
  if (by.containsKey('array')) return const ApiSchema.array(ApiSchema.any());
  // Nothing here says what the value holds, only when it is validated.
  if (by.keys.every(_isControl)) return const ApiSchema.any();
  final exact = by['digits']?.params.first;
  final range = by['digits_between']?.params;
  return ApiSchema.string(
    format: _format(by),
    // `sizeOf` measures a non-numeric value by its length, so `max:120` on a
    // string is maxLength — exactly what the validator will enforce.
    minLength:
        _sizeBound(by, 'min') ??
        _between(by, 0) ??
        int.tryParse(exact ?? range?.first ?? ''),
    maxLength:
        _sizeBound(by, 'max') ??
        _between(by, 1) ??
        int.tryParse(exact ?? range?[1] ?? ''),
    pattern:
        by['regex']?.params.first ??
        (exact != null || range != null ? r'^\d+$' : null),
    values: rawValues,
  );
}

List<T>? _parsedValues<T>(List<String>? raw, T? Function(String) parse) {
  if (raw == null) return null;
  final values = [for (final value in raw) ?parse(value)];
  return values.isEmpty ? null : values;
}

List<bool>? _booleanValues(List<String>? raw) {
  if (raw == null) return null;
  final values = <bool>{};
  for (final value in raw) {
    if (value == 'true' || value == '1') values.add(true);
    if (value == 'false' || value == '0') values.add(false);
  }
  return values.isEmpty ? null : values.toList();
}

bool _childRequiresPresence(_Node node) {
  for (final entry in node.children.entries) {
    // A wildcard validates existing array entries. It does not require the
    // array itself to exist.
    if (entry.key == '*') continue;
    final rules = entry.value.rules == null
        ? const <Object>[]
        : parseRuleSet(entry.value.rules!);
    final names = rules
        .whereType<ParsedRule>()
        .map((rule) => rule.name)
        .toSet();
    if (names.contains('sometimes')) continue;
    if (names.contains('required') || names.contains('present')) return true;
    if (_childRequiresPresence(entry.value)) return true;
  }
  return false;
}

/// Rules that say when a value is validated, not what it holds.
bool _isControl(String rule) => const {
  'required',
  'sometimes',
  'nullable',
  'present',
  'bail',
  'required_if',
  'required_unless',
  'required_with',
  'required_without',
}.contains(rule);

String? _format(Map<String, ParsedRule> by) {
  for (final entry in _formats.entries) {
    if (by.containsKey(entry.key)) return entry.value;
  }
  return null;
}

int? _sizeBound(Map<String, ParsedRule> by, String rule) =>
    int.tryParse(by[rule]?.params.first ?? '') ??
    int.tryParse(by['size']?.params.first ?? '');

int? _between(Map<String, ParsedRule> by, int index) =>
    int.tryParse(by['between']?.params[index] ?? '');

num? _numBound(Map<String, ParsedRule> by, String rule) =>
    num.tryParse(by[rule]?.params.first ?? '') ??
    num.tryParse(by['size']?.params.first ?? '');

num? _numBetween(Map<String, ParsedRule> by, int index) =>
    num.tryParse(by['between']?.params[index] ?? '');

ApiSchema _apply(
  ApiSchema schema, {
  required bool nullable,
  required bool optional,
}) {
  var result = schema;
  if (nullable) result = result.nullable;
  if (optional) result = result.optional;
  return result;
}
