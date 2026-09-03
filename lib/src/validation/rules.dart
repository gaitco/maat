import 'validator.dart';

num? asNum(dynamic v) =>
    v is num ? v : (v is String ? num.tryParse(v.trim()) : null);

bool isEmptyValue(dynamic v) =>
    v == null ||
    (v is String && v.trim().isEmpty) ||
    (v is Iterable && v.isEmpty) ||
    (v is Map && v.isEmpty);

/// The comparable "size" of a value: number, string length, or item count.
num sizeOf(RuleContext ctx) {
  final v = ctx.value;
  if (ctx.validator.hasNumericRule(ctx.attribute)) return asNum(v) ?? 0;
  if (v is String) return v.length;
  if (v is Iterable) return v.length;
  if (v is Map) return v.length;
  return asNum(v) ?? 0;
}

num _p(RuleContext ctx, int index) => num.parse(ctx.params[index]);

final RegExp _email = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

final Map<String, RuleCheck> builtinRules = {
  'required': (ctx) => ctx.present && !isEmptyValue(ctx.value),
  'present': (ctx) => ctx.present,
  'nullable': (_) => true,
  'sometimes': (_) => true,
  'bail': (_) => true,
  'string': (ctx) => ctx.value is String,
  'integer': (ctx) =>
      ctx.value is int ||
      (ctx.value is String &&
          RegExp(r'^[+-]?\d+$').hasMatch(ctx.value as String)),
  'numeric': (ctx) => asNum(ctx.value) != null,
  'boolean': (ctx) =>
      const [true, false, 0, 1, '0', '1', 'true', 'false'].contains(ctx.value),
  'array': (ctx) => ctx.value is List || ctx.value is Map,
  'email': (ctx) => ctx.value is String && _email.hasMatch(ctx.value as String),
  'min': (ctx) => sizeOf(ctx) >= _p(ctx, 0),
  'max': (ctx) => sizeOf(ctx) <= _p(ctx, 0),
  'between': (ctx) => sizeOf(ctx) >= _p(ctx, 0) && sizeOf(ctx) <= _p(ctx, 1),
  'size': (ctx) => sizeOf(ctx) == _p(ctx, 0),
  'in': (ctx) => ctx.params.contains(ctx.value?.toString()),
  'not_in': (ctx) => !ctx.params.contains(ctx.value?.toString()),
  'confirmed': (ctx) =>
      ctx.validator.valueOf('${ctx.attribute}_confirmation') == ctx.value,
  'url': (ctx) {
    final v = ctx.value;
    if (v is! String) return false;
    final uri = Uri.tryParse(v);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  },
  'uuid': (ctx) =>
      ctx.value is String &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(ctx.value as String),
  'regex': (ctx) => RegExp(ctx.params[0]).hasMatch(ctx.value.toString()),
  'not_regex': (ctx) => !RegExp(ctx.params[0]).hasMatch(ctx.value.toString()),
  'same': (ctx) => ctx.validator.valueOf(ctx.params[0]) == ctx.value,
  'different': (ctx) => ctx.validator.valueOf(ctx.params[0]) != ctx.value,
  'date': (ctx) => parseDate(ctx.value) != null,
  'after': (ctx) => _compareDates(ctx, (a, b) => a.isAfter(b)),
  'before': (ctx) => _compareDates(ctx, (a, b) => a.isBefore(b)),
  'alpha': (ctx) =>
      ctx.value is String &&
      RegExp(r'^[\p{L}\p{M}]+$', unicode: true).hasMatch(ctx.value as String),
  'alpha_num': (ctx) =>
      ctx.value is String &&
      RegExp(
        r'^[\p{L}\p{M}\p{N}]+$',
        unicode: true,
      ).hasMatch(ctx.value as String),
  'alpha_dash': (ctx) =>
      ctx.value is String &&
      RegExp(
        r'^[\p{L}\p{M}\p{N}_-]+$',
        unicode: true,
      ).hasMatch(ctx.value as String),
  'digits': (ctx) {
    final s = ctx.value.toString();
    return RegExp(r'^\d+$').hasMatch(s) && s.length == int.parse(ctx.params[0]);
  },
  'digits_between': (ctx) {
    final s = ctx.value.toString();
    return RegExp(r'^\d+$').hasMatch(s) &&
        s.length >= int.parse(ctx.params[0]) &&
        s.length <= int.parse(ctx.params[1]);
  },
  'starts_with': (ctx) =>
      ctx.params.any((p) => ctx.value.toString().startsWith(p)),
  'ends_with': (ctx) => ctx.params.any((p) => ctx.value.toString().endsWith(p)),
  'required_if': (ctx) {
    final other = ctx.validator.valueOf(ctx.params[0])?.toString();
    if (!ctx.params.skip(1).contains(other)) return true;
    return ctx.present && !isEmptyValue(ctx.value);
  },
  'required_unless': (ctx) {
    final other = ctx.validator.valueOf(ctx.params[0])?.toString();
    if (ctx.params.skip(1).contains(other)) return true;
    return ctx.present && !isEmptyValue(ctx.value);
  },
  'required_with': (ctx) {
    final anyPresent = ctx.params.any(
      (p) =>
          ctx.validator.isPresent(p) && !isEmptyValue(ctx.validator.valueOf(p)),
    );
    if (!anyPresent) return true;
    return ctx.present && !isEmptyValue(ctx.value);
  },
  'required_without': (ctx) {
    final anyMissing = ctx.params.any(
      (p) =>
          !ctx.validator.isPresent(p) || isEmptyValue(ctx.validator.valueOf(p)),
    );
    if (!anyMissing) return true;
    return ctx.present && !isEmptyValue(ctx.value);
  },
};

/// Parses ISO-8601 / `YYYY-MM-DD` strings (and passes DateTime through).
DateTime? parseDate(dynamic v) {
  if (v is DateTime) return v;
  if (v is! String) return null;
  return DateTime.tryParse(v.trim());
}

bool _compareDates(
  RuleContext ctx,
  bool Function(DateTime a, DateTime b) compare,
) {
  final value = parseDate(ctx.value);
  if (value == null) return false;
  final target =
      parseDate(ctx.params[0]) ??
      parseDate(ctx.validator.valueOf(ctx.params[0]));
  if (target == null) return false;
  return compare(value, target);
}
