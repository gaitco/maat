/// A custom validation rule object, usable inside a rules list.
abstract class Rule {
  bool passes(String attribute, dynamic value, Map<String, dynamic> data);
  String message();
}
