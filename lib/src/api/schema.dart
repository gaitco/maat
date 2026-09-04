/// The JSON types an API contract can describe.
enum ApiType { string, integer, number, boolean, object, array, any, none }

/// The shape of one JSON value: what an endpoint accepts or returns.
///
/// Deliberately smaller than JSON Schema. It carries what both renderers need
/// — an OpenAPI 3.1 schema object and a null-safe Dart type — and nothing
/// else. Named objects are the unit of reuse: each one becomes a
/// `components/schemas` entry and one generated DTO class.
final class ApiSchema {
  const ApiSchema._(
    this.type, {
    this.name,
    this.format,
    this.properties,
    this.items,
    this.values,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.pattern,
    this.description,
    this.isNullable = false,
    this.isOptional = false,
  });

  /// A value the endpoint does not describe: `Object?` in Dart, `{}` in JSON
  /// Schema, which is 3.1's "any value".
  const ApiSchema.any() : this._(ApiType.any);

  /// No body at all — a 204, or a request that sends nothing.
  const ApiSchema.none() : this._(ApiType.none);

  const ApiSchema.string({
    String? format,
    int? minLength,
    int? maxLength,
    String? pattern,
    List<String>? values,
    String? description,
  }) : this._(
         ApiType.string,
         format: format,
         minLength: minLength,
         maxLength: maxLength,
         pattern: pattern,
         values: values,
         description: description,
       );

  const ApiSchema.integer({
    num? minimum,
    num? maximum,
    List<int>? values,
    String? description,
  }) : this._(
         ApiType.integer,
         minimum: minimum,
         maximum: maximum,
         values: values,
         description: description,
       );

  const ApiSchema.number({
    num? minimum,
    num? maximum,
    List<num>? values,
    String? description,
  }) : this._(
         ApiType.number,
         minimum: minimum,
         maximum: maximum,
         values: values,
         description: description,
       );

  const ApiSchema.boolean({List<bool>? values, String? description})
    : this._(ApiType.boolean, values: values, description: description);

  /// A named object is hoisted into `components/schemas` and generates a DTO;
  /// an anonymous one (`name: null`) is inlined wherever it appears.
  const ApiSchema.object(
    Map<String, ApiSchema> properties, {
    String? name,
    String? description,
  }) : this._(
         ApiType.object,
         name: name,
         properties: properties,
         description: description,
       );

  const ApiSchema.array(
    ApiSchema items, {
    int? minItems,
    int? maxItems,
    String? description,
  }) : this._(
         ApiType.array,
         items: items,
         minItems: minItems,
         maxItems: maxItems,
         description: description,
       );

  final ApiType type;
  final String? name;
  final String? format;
  final Map<String, ApiSchema>? properties;
  final ApiSchema? items;
  final List<Object?>? values;
  final num? minimum;
  final num? maximum;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final String? pattern;
  final String? description;

  /// The value may be `null` — OpenAPI 3.1 renders this as a type array.
  final bool isNullable;

  /// The key may be absent from the object entirely.
  final bool isOptional;

  /// Either modifier means the generated Dart field or parameter is `T?`.
  bool get isDartNullable => isNullable || isOptional;

  ApiSchema get nullable => _copy(isNullable: true);

  /// The same shape with presence stripped, for the places where required
  /// and optional are carried by the surrounding structure rather than by the
  /// schema itself — a path parameter, for one.
  ApiSchema get bare => _copy(isNullable: false, isOptional: false);
  ApiSchema get optional => _copy(isOptional: true);
  ApiSchema describe(String text) => _copy(description: text);
  ApiSchema named(String schemaName) => _copy(name: schemaName);

  ApiSchema _copy({
    String? name,
    String? description,
    bool? isNullable,
    bool? isOptional,
  }) => ApiSchema._(
    type,
    name: name ?? this.name,
    format: format,
    properties: properties,
    items: items,
    values: values,
    minimum: minimum,
    maximum: maximum,
    minLength: minLength,
    maxLength: maxLength,
    minItems: minItems,
    maxItems: maxItems,
    pattern: pattern,
    description: description ?? this.description,
    isNullable: isNullable ?? this.isNullable,
    isOptional: isOptional ?? this.isOptional,
  );

  /// Every named object reachable from this schema, including itself.
  ///
  /// Recursive schemas (a comment with replies) are visited once — the guard
  /// is by name, which is also what makes a name collision detectable.
  void collectNamed(Map<String, ApiSchema> into) {
    final schemaName = name;
    if (schemaName != null && type == ApiType.object) {
      // Optionality and nullability belong to the reference site, not to the
      // reusable component itself. `Book` and `Book?` are one schema.
      final definition = bare;
      final existing = into[schemaName];
      if (existing != null) {
        if (!existing._sameShapeAs(definition)) {
          throw StateError(
            'Two different schemas are both named [$schemaName]. A schema name '
            'has to identify one shape, or the document and the generated '
            'client would disagree about what it holds.',
          );
        }
        return;
      }
      into[schemaName] = definition;
    }
    for (final property in properties?.values ?? const <ApiSchema>[]) {
      property.collectNamed(into);
    }
    items?.collectNamed(into);
  }

  bool _sameShapeAs(ApiSchema other, [Set<(ApiSchema, ApiSchema)>? compared]) {
    if (identical(this, other)) return true;
    final seen = compared ?? <(ApiSchema, ApiSchema)>{};
    if (!seen.add((this, other))) return true;
    if (type != other.type ||
        name != other.name ||
        format != other.format ||
        minimum != other.minimum ||
        maximum != other.maximum ||
        minLength != other.minLength ||
        maxLength != other.maxLength ||
        minItems != other.minItems ||
        maxItems != other.maxItems ||
        pattern != other.pattern ||
        description != other.description ||
        isNullable != other.isNullable ||
        isOptional != other.isOptional ||
        !_sameValues(values, other.values)) {
      return false;
    }
    final myItems = items;
    final theirItems = other.items;
    if ((myItems == null) != (theirItems == null) ||
        (myItems != null && !myItems._sameShapeAs(theirItems!, seen))) {
      return false;
    }
    final mine = properties ?? const {};
    final theirs = other.properties ?? const {};
    if (mine.length != theirs.length) return false;
    for (final entry in mine.entries) {
      final match = theirs[entry.key];
      if (match == null) return false;
      if (!entry.value._sameShapeAs(match, seen)) return false;
    }
    return true;
  }

  static bool _sameValues(List<Object?>? a, List<Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
