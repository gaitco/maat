/// Thrown when validation fails; rendered as 422 by the exception handler.
class ValidationException implements Exception {
  ValidationException(
    this.errors, {
    this.message = 'The given data was invalid.',
  });
  final Map<String, List<String>> errors;
  final String message;

  @override
  String toString() => 'ValidationException: $message $errors';
}
