import '../../broadcasting/channel_authorization.dart';
import '../command.dart';

class ChannelListCommand extends Command {
  @override
  String get name => 'channel:list';

  @override
  String get description => 'List all registered channel patterns';

  @override
  Future<int> handle() async {
    final patterns = {...app.make<ChannelAuthorizationRegistry>().patterns};
    table(
      ['Pattern'],
      [
        for (final pattern in patterns) [pattern],
      ],
    );
    return 0;
  }
}
