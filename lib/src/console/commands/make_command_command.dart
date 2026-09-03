import '../../support/str.dart';
import '../generator_command.dart';
import '../stubs.dart';

class MakeCommandCommand extends GeneratorCommand {
  @override
  String get name => 'make:command';
  @override
  String get description => 'Create a new Sesh command';
  @override
  String get type => 'Console command';
  @override
  String get directory => 'lib/app/console/commands';
  @override
  String stub(String className) =>
      Stubs.command(className, 'app:${Str.kebab(className)}');
}
