import '../validation/form_request.dart';
import 'rule_schema.dart';
import 'schema.dart';

/// One documented response.
class ApiResponse {
  const ApiResponse(this.status, this.schema, {this.description});

  final int status;
  final ApiSchema schema;
  final String? description;
}

/// What a route accepts and returns, declared on the route itself.
///
/// Maat handlers return `Object?` and validate inside the method body, so
/// without reflection there is nothing for a generator to read. This is that
/// missing description, and it lives next to `.name()` and `.middleware()`
/// so it is reviewed in the same diff as the route it describes.
///
/// A route carrying one of these is exported; a route without one is not.
/// That is what keeps HTML routes out of the API document without guessing
/// from a URL prefix.
class RouteContract {
  String? summary;
  String? description;
  String? operationId;
  bool deprecated = false;
  final List<String> tags = [];

  /// Rules for path parameters, keyed by the name in the URI.
  final Map<String, Object> pathRules = {};
  final Map<String, Object> queryRules = {};
  final Map<String, Object> bodyRules = {};

  /// Declared responses by status. A later `.responds()` for the same status
  /// replaces the earlier one rather than emitting both.
  final Map<int, ApiResponse> responses = {};

  bool get hasInput => queryRules.isNotEmpty || bodyRules.isNotEmpty;

  ApiSchema? bodySchema(String name) =>
      bodyRules.isEmpty ? null : rulesToSchema(bodyRules, name: name);

  /// Merges [request]'s rules in, so one [FormRequest] can be both what the
  /// handler validates with and what the document describes.
  void useFormRequest(FormRequest request) => bodyRules.addAll(request.rules());
}
