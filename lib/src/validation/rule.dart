/// A custom validation rule object, usable inside a rules list.
abstract class Rule {
  bool passes(String attribute, dynamic value, Map<String, dynamic> data);
  String message();
}

/// One rule from a rule string: `max:120` is `ParsedRule('max', ['120'])`.
class ParsedRule {
  ParsedRule(this.name, this.params);

  final String name;
  final List<String> params;

  static ParsedRule parse(String rule) {
    final colon = rule.indexOf(':');
    if (colon < 0) return ParsedRule(rule, const []);
    final name = rule.substring(0, colon);
    final rest = rule.substring(colon + 1);
    // A regex may legitimately contain commas, so it is never split.
    if (name == 'regex' || name == 'not_regex') return ParsedRule(name, [rest]);
    return ParsedRule(name, rest.split(','));
  }
}

/// Parses one attribute's rules — `'required|max:5'`, or a list mixing
/// strings and [Rule] objects — into [ParsedRule]s and [Rule]s.
///
/// Shared by the validator and by OpenAPI schema generation, so a rule string
/// means exactly the same thing to the document as it does at request time.
List<Object> parseRuleSet(Object rules) {
  if (rules is String) {
    return [
      for (final r in rules.split('|'))
        if (r.isNotEmpty) ParsedRule.parse(r),
    ];
  }
  if (rules is List) {
    return [
      for (final r in rules)
        if (r is Rule)
          r
        else if (r is String)
          ...parseRuleSet(r)
        else
          throw ArgumentError('Invalid rule $r'),
    ];
  }
  throw ArgumentError(
    'Rules must be a String or a List, got ${rules.runtimeType}',
  );
}
