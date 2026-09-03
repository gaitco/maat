import '../http/request.dart';

/// A reusable rule set, used via `request.validateWith(StorePostRequest())`.
abstract class FormRequest {
  Map<String, Object> rules();
  Map<String, String> messages() => const {};
  Map<String, String> attributes() => const {};
  bool authorize(Request request) => true;
}
