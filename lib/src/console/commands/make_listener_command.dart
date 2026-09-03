import '../../support/str.dart';
import '../generator_command.dart';
import '../stubs.dart';

class MakeListenerCommand extends GeneratorCommand {
  @override
  String get name => 'make:listener';

  @override
  String get description => 'Create a new event listener class';

  @override
  String get signature => '{name} {--event=} {--force}';

  @override
  String get type => 'Listener';

  @override
  String get directory => 'lib/app/listeners';

  @override
  String stub(String className) {
    final event = option('event');
    return Stubs.listener(
      className,
      event == null || event.isEmpty ? null : Str.studly(event),
    );
  }
}
