import '../foundation/application.dart';
import 'broadcast_fake.dart';
import 'broadcast_manager.dart';
import 'channel_authorization.dart';

abstract final class Broadcast {
  static BroadcastManager get manager => app<BroadcastManager>();

  static PendingBroadcast broadcast(Object event) => manager.pending(event);

  static PendingBroadcast on(String name) => manager.on(name);

  static void channel(String pattern, ChannelAuthorizer authorizer) =>
      app<ChannelAuthorizationRegistry>().channel(pattern, authorizer);

  static BroadcastFake fake() {
    final fake = BroadcastFake();
    Application.current.instance<BroadcastManager>(
      BroadcastManager({'fake': fake}, defaultConnection: 'fake'),
    );
    return fake;
  }
}

PendingBroadcast broadcast(Object event) => Broadcast.broadcast(event);
