import '../generator_command.dart';
import '../stubs.dart';

class MakeMiddlewareCommand extends GeneratorCommand {
  @override
  String get name => 'make:middleware';
  @override
  String get description => 'Create a new middleware class';
  @override
  String get type => 'Middleware';
  @override
  String get directory => 'lib/app/http/middleware';
  @override
  String stub(String className) => Stubs.middleware(className);
}
