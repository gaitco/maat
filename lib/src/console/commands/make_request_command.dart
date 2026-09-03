import '../generator_command.dart';
import '../stubs.dart';

class MakeRequestCommand extends GeneratorCommand {
  @override
  String get name => 'make:request';
  @override
  String get description => 'Create a new form request class';
  @override
  String get type => 'Request';
  @override
  String get directory => 'lib/app/http/requests';
  @override
  String stub(String className) => Stubs.request(className);
}
