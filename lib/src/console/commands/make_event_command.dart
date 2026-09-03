import '../generator_command.dart';
import '../stubs.dart';

class MakeEventCommand extends GeneratorCommand {
  @override
  String get name => 'make:event';

  @override
  String get description => 'Create a new event class';

  @override
  String get type => 'Event';

  @override
  String get directory => 'lib/app/events';

  @override
  String stub(String className) => Stubs.event(className);
}
