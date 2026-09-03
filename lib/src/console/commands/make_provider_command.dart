import '../generator_command.dart';
import '../stubs.dart';

class MakeProviderCommand extends GeneratorCommand {
  @override
  String get name => 'make:provider';
  @override
  String get description => 'Create a new service provider class';
  @override
  String get type => 'Provider';
  @override
  String get directory => 'lib/app/providers';
  @override
  String stub(String className) => Stubs.provider(className);
}
