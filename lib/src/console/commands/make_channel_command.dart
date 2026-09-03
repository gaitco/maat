import '../generator_command.dart';
import '../stubs.dart';

class MakeChannelCommand extends GeneratorCommand {
  @override
  String get name => 'make:channel';

  @override
  String get description => 'Create a channel authorization stub';

  @override
  String get type => 'Channel';

  @override
  String get directory => 'routes';

  @override
  String stub(String className) => Stubs.channel(className);
}
