import '../support/str.dart';
import 'messages.dart';
import 'rule.dart';
import 'rules.dart';
import 'validation_exception.dart';

typedef RuleCheck = bool Function(RuleContext ctx);
typedef AsyncRuleCheck = Future<bool> Function(RuleContext ctx);

class RuleContext {
  RuleContext(
    this.attribute,
    this.value,
    this.params,
    this.data,
    this.validator, {
    required this.present,
  });
  final String attribute;
  final dynamic value;
  final List<String> params;
  final Map<String, dynamic> data;
  final Validator validator;
  final bool present;
}

/// Laravel's validator: rule strings, implicit rules, wildcards, messages.
class Validator {
  Validator(
    this.data,
    Map<String, Object> rules, {
    this.messages = const {},
    this.attributes = const {},
  }) : _originalKeys = rules.keys.toList() {
    for (final entry in rules.entries) {
      final parsed = parseRuleSet(entry.value);
      for (final key in _expandKey(entry.key)) {
        _rules[key] = parsed;
        _primary[key] = entry.key;
      }
    }
  }

  static Validator make(
    Map<String, dynamic> data,
    Map<String, Object> rules, {
    Map<String, String> messages = const {},
    Map<String, String> attributes = const {},
  }) => Validator(data, rules, messages: messages, attributes: attributes);

  static final Map<String, RuleCheck> _custom = {};
  static final Map<String, AsyncRuleCheck> _customAsync = {};
  static final Map<String, String> _customMessages = {};
  static final Set<String> _customImplicit = {};

  static const Set<String> implicitRules = {
    'required',
    'required_if',
    'required_unless',
    'required_with',
    'required_without',
    'present',
    'sometimes',
    'nullable',
  };
  static const Set<String> _numericRules = {'numeric', 'integer'};
  static const Set<String> _controlRules = {'sometimes', 'nullable', 'bail'};

  static void extend(
    String name,
    RuleCheck check, {
    String? message,
    bool implicit = false,
  }) {
    if (_customAsync.containsKey(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'is already registered with Validator.extendAsync. One name cannot be '
            'both, or the two would shadow each other silently. Call '
            'Validator.resetExtensions() first to replace it',
      );
    }
    _custom[name] = check;
    if (message != null) _customMessages[name] = message;
    if (implicit) _customImplicit.add(name);
  }

  /// Registers a rule that needs to await something — a database round-trip,
  /// an HTTP call. An attribute carrying one can only be validated through
  /// [passesAsync] / [validateAsync]; the synchronous methods throw.
  ///
  /// ponytail: no `implicit` flag — every async rule so far (`unique`,
  /// `exists`) skips absent values, which is what non-implicit means. Add the
  /// flag when a rule actually needs to run on an absent attribute.
  static void extendAsync(
    String name,
    AsyncRuleCheck check, {
    String? message,
  }) {
    // An async rule is always gated as non-implicit, so sharing a name with a
    // rule that is gated any other way would make the pre-pass and the rule
    // loop disagree about whether to run it. Refuse the pairing at
    // registration rather than crash mid-validation.
    if (_custom.containsKey(name) ||
        implicitRules.contains(name) ||
        _controlRules.contains(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'is already a synchronous, implicit or control rule. An async rule '
            'cannot share a name with one: they are gated differently, so the '
            'pair would validate inconsistently. Pick another name, or call '
            'Validator.resetExtensions() first',
      );
    }
    _customAsync[name] = check;
    if (message != null) _customMessages[name] = message;
  }

  /// Forgets every rule added with [extend] or [extendAsync]. The registries
  /// are static, so a test that registers a rule leaks it into the rest of the
  /// file without this.
  static void resetExtensions() {
    _custom.clear();
    _customAsync.clear();
    _customMessages.clear();
    _customImplicit.clear();
  }

  final Map<String, dynamic> data;
  final Map<String, String> messages;
  final Map<String, String> attributes;
  final List<String> _originalKeys;
  final Map<String, List<Object>> _rules = {};
  final Map<String, String> _primary = {};
  Map<String, List<String>>? _errors;

  /// Each async rule's verdict — a `bool`, or the `(error, stack)` its check
  /// threw — filled by [_resolveAsyncRules] before the one and only rule loop
  /// runs. Null until then, which is also how [_run] knows it may not touch an
  /// async rule.
  Map<String, Object>? _asyncResults;

  /// The one place an async verdict's slot is named. Both [_resolveAsyncRules]
  /// and [_run] walk the same `_rules[attribute]` list, so the position is
  /// stable — and keying on position rather than on the rule's name is what
  /// stops two `unique` rules on one attribute from sharing a verdict.
  static String _asyncKey(String attribute, int index) => '$attribute|$index';

  Map<String, List<String>> get errors {
    _errors ??= _run();
    final unmodifiable = <String, List<String>>{};
    for (final entry in _errors!.entries) {
      unmodifiable[entry.key] = List<String>.unmodifiable(entry.value);
    }
    return Map<String, List<String>>.unmodifiable(unmodifiable);
  }

  bool passes() => errors.isEmpty;
  bool fails() => !passes();

  /// [passes] for rule sets that contain a rule registered with [extendAsync].
  /// Works for ordinary rules too, so a caller that cannot know which kind it
  /// has — `request.validate()` — can always take this path.
  Future<bool> passesAsync() async {
    if (_errors == null) {
      await _resolveAsyncRules();
      _errors = _run();
    }
    return _errors!.isEmpty;
  }

  /// Validated data, or throws [ValidationException].
  Map<String, dynamic> validate() {
    if (fails()) {
      throw ValidationException(errors);
    }
    return validated();
  }

  /// [validate] on the async path.
  Future<Map<String, dynamic>> validateAsync() async {
    if (!await passesAsync()) {
      throw ValidationException(errors);
    }
    return validated();
  }

  bool hasRule(String attribute, String rule) => (_rules[attribute] ?? const [])
      .any((r) => r is ParsedRule && r.name == rule);
  bool hasNumericRule(String attribute) =>
      _numericRules.any((r) => hasRule(attribute, r));

  /// Dot-path read of [data]; returns null when absent.
  dynamic valueOf(String key) => _lookup(key).$2;
  bool isPresent(String key) => _lookup(key).$1;

  /// Data limited to validated keys (nested keys reconstructed, wildcard roots copied whole).
  Map<String, dynamic> validated() {
    final result = <String, dynamic>{};
    for (final key in _originalKeys) {
      if (key.contains('*')) {
        final wildcardIndex = key.indexOf('.*');
        if (wildcardIndex >= 0) {
          // Pattern like 'items.*'
          final root = key.substring(0, wildcardIndex);
          final (present, value) = _lookup(root);
          if (!present) continue;
          _setNested(result, root, value);
        } else {
          // Pattern like '*' - find all expanded keys for this wildcard
          for (final ruleKey in _rules.keys) {
            if (_primary[ruleKey] == key) {
              final (present, value) = _lookup(ruleKey);
              if (!present) continue;
              _setNested(result, ruleKey, value);
            }
          }
        }
      } else {
        // Non-wildcard key
        final (present, value) = _lookup(key);
        if (!present) continue;
        _setNested(result, key, value);
      }
    }
    return result;
  }

  /// Awaits every async rule the loop in [_run] is going to reach, so that
  /// loop stays synchronous and stays the only copy of the rule semantics.
  /// The gate here is [_shouldRun] with the same arguments [_run] uses — an
  /// async rule is always non-implicit, which [extendAsync] enforces by
  /// refusing to share a name with an implicit or control rule.
  ///
  /// `bail` is the one thing not replayed: a rule sitting behind a rule that
  /// bails is still queried here. Its verdict is then never read, and an error
  /// it threw is never rethrown, so reaching it costs a round-trip and nothing
  /// else — a failing database does not turn input that bails into a 500.
  Future<void> _resolveAsyncRules() async {
    if (_customAsync.isEmpty) {
      _asyncResults = const <String, Object>{};
      return;
    }
    final results = <String, Object>{};
    for (final entry in _rules.entries) {
      final attribute = entry.key;
      final rules = entry.value;
      final names = rules.whereType<ParsedRule>().map((r) => r.name).toSet();
      final (present, value) = _lookup(attribute);
      if (names.contains('sometimes') && !present) continue;
      final nullable = names.contains('nullable');
      for (var i = 0; i < rules.length; i++) {
        final rule = rules[i];
        if (rule is! ParsedRule) continue;
        final check = _customAsync[rule.name];
        if (check == null) continue;
        if (!_shouldRun(false, present, value, nullable)) continue;
        final ctx = RuleContext(
          attribute,
          value,
          rule.params,
          data,
          this,
          present: present,
        );
        try {
          results[_asyncKey(attribute, i)] = await check(ctx);
        } catch (error, stack) {
          results[_asyncKey(attribute, i)] = (error, stack);
        }
      }
    }
    _asyncResults = results;
  }

  /// The verdict [_resolveAsyncRules] recorded for the rule at [index], or the
  /// error its check threw — rethrown here and only here, once [_run] has
  /// proved the rule is actually reached.
  bool _asyncVerdict(String attribute, int index) {
    final cached = _asyncResults![_asyncKey(attribute, index)]!;
    if (cached is bool) return cached;
    final (error, stack) = cached as (Object, StackTrace);
    Error.throwWithStackTrace(error, stack);
  }

  Map<String, List<String>> _run() {
    _assertNoUnresolvedAsyncRule();
    final errors = <String, List<String>>{};
    for (final entry in _rules.entries) {
      final attribute = entry.key;
      final (present, value) = _lookup(attribute);
      final rules = entry.value;
      final names = rules.whereType<ParsedRule>().map((r) => r.name).toSet();
      if (names.contains('sometimes') && !present) continue;
      final nullable = names.contains('nullable');
      final bail = names.contains('bail');
      for (var i = 0; i < rules.length; i++) {
        final rule = rules[i];
        if (rule is Rule) {
          if (!_shouldRun(false, present, value, nullable)) continue;
          if (!rule.passes(attribute, value, data)) {
            errors
                .putIfAbsent(attribute, () => [])
                .add(_replace(rule.message(), attribute, const [], value));
            if (bail) break;
          }
          continue;
        }
        final parsed = rule as ParsedRule;
        if (_controlRules.contains(parsed.name)) continue;
        final implicit =
            implicitRules.contains(parsed.name) ||
            _customImplicit.contains(parsed.name);
        if (!_shouldRun(implicit, present, value, nullable)) continue;
        // An async rule was already awaited by _resolveAsyncRules under this
        // very same _shouldRun gate, so its verdict is in the map.
        final check = _customAsync.containsKey(parsed.name)
            ? ((_) => _asyncVerdict(attribute, i))
            : (_custom[parsed.name] ?? builtinRules[parsed.name]);
        if (check == null) {
          throw ArgumentError(
            'Unknown validation rule [${parsed.name}] on [$attribute].',
          );
        }
        final ctx = RuleContext(
          attribute,
          value,
          parsed.params,
          data,
          this,
          present: present,
        );
        if (!check(ctx)) {
          errors
              .putIfAbsent(attribute, () => [])
              .add(_message(parsed, attribute, value));
          if (bail) break;
        }
      }
    }
    return errors;
  }

  /// Every synchronous entry point funnels through [_run], so this one check
  /// covers [passes], [fails], [validate] and the [errors] getter alike.
  void _assertNoUnresolvedAsyncRule() {
    if (_asyncResults != null || _customAsync.isEmpty) return;
    for (final rules in _rules.values) {
      for (final rule in rules.whereType<ParsedRule>()) {
        if (_customAsync.containsKey(rule.name)) {
          throw StateError(
            'The "${rule.name}" rule runs asynchronously and cannot be '
            'validated synchronously. Use await validator.passesAsync() or '
            'await validator.validateAsync() (request.validate() already does).',
          );
        }
      }
    }
  }

  bool _shouldRun(bool implicit, bool present, dynamic value, bool nullable) {
    if (implicit) return true;
    if (!present) return false;
    if (value is String && value.trim().isEmpty) return false;
    if (value == null && nullable) return false;
    return true;
  }

  String _message(ParsedRule rule, String attribute, dynamic value) {
    final custom =
        messages['${_primary[attribute]}.${rule.name}'] ??
        messages['$attribute.${rule.name}'] ??
        messages[rule.name];
    var template = custom ?? _customMessages[rule.name];
    if (template == null) {
      final entry = defaultMessages[rule.name];
      if (entry is Map<String, String>) {
        final type = hasNumericRule(attribute)
            ? 'numeric'
            : (value is Iterable || value is Map)
            ? 'array'
            : (value is num ? 'numeric' : 'string');
        template = entry[type];
      } else {
        template = entry as String?;
      }
    }
    template ??= 'The :attribute field is invalid.';
    return _replace(template, attribute, rule.params, value, rule.name);
  }

  String _replace(
    String template,
    String attribute,
    List<String> params,
    dynamic value, [
    String? rule,
  ]) {
    final display =
        attributes[_primary[attribute]] ??
        attributes[attribute] ??
        Str.snake(attribute).replaceAll('_', ' ');
    var out = template.replaceAll(':attribute', display);
    if (params.isNotEmpty) {
      final p0 = params[0];
      final p1 = params.length > 1 ? params[1] : '';
      out = out
          .replaceAll(':min', p0)
          .replaceAll(
            ':max',
            rule == 'between' || rule == 'digits_between' ? p1 : p0,
          )
          .replaceAll(':size', p0)
          .replaceAll(':digits', p0)
          .replaceAll(':date', p0)
          .replaceAll(':other', (attributes[p0] ?? p0).replaceAll('_', ' '))
          .replaceAll(
            ':values',
            (rule == 'required_if' || rule == 'required_unless'
                    ? params.skip(1)
                    : params)
                .join(', '),
          )
          .replaceAll(':value', p1);
    }
    return out;
  }

  /// `items.*.name` -> `items.0.name`, `items.1.name`, ... against [data].
  List<String> _expandKey(String key) {
    if (!key.contains('*')) return [key];
    final segments = key.split('.');
    final results = <String>[];
    void walk(int index, String prefix, dynamic node) {
      if (index == segments.length) {
        results.add(prefix);
        return;
      }
      final segment = segments[index];
      final next = prefix.isEmpty ? '' : '$prefix.';
      if (segment == '*') {
        if (node is List) {
          for (var i = 0; i < node.length; i++) {
            walk(index + 1, '$next$i', node[i]);
          }
        } else if (node is Map) {
          for (final k in node.keys) {
            walk(index + 1, '$next$k', node[k]);
          }
        }
      } else {
        walk(index + 1, '$next$segment', node is Map ? node[segment] : null);
      }
    }

    walk(0, '', data);
    return results;
  }

  (bool, dynamic) _lookup(String key) {
    dynamic node = data;
    for (final segment in key.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else if (node is List) {
        final i = int.tryParse(segment);
        if (i == null || i >= node.length) return (false, null);
        node = node[i];
      } else {
        return (false, null);
      }
    }
    return (true, node);
  }

  static void _setNested(
    Map<String, dynamic> target,
    String key,
    dynamic value,
  ) {
    final segments = key.split('.');
    var node = target;
    for (final segment in segments.take(segments.length - 1)) {
      node = (node[segment] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    node[segments.last] = value;
  }
}
