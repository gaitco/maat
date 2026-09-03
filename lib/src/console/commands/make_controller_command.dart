import '../generator_command.dart';
import '../stubs.dart';

class MakeControllerCommand extends GeneratorCommand {
  @override
  String get name => 'make:controller';
  @override
  String get description => 'Create a new controller class';
  @override
  String get signature => '{name} {--api} {--resource} {--invokable} {--force}';
  @override
  String get type => 'Controller';
  @override
  String get directory => 'lib/app/http/controllers';

  @override
  String stub(String className) {
    if (flag('api') || flag('resource')) return Stubs.apiController(className);
    if (flag('invokable')) return Stubs.invokableController(className);
    return Stubs.controller(className);
  }
}
