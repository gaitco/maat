import 'channel.dart';

abstract interface class ShouldBroadcast {
  List<Channel> broadcastOn();
}

abstract interface class BroadcastsAs {
  String broadcastAs();
}

abstract interface class BroadcastsWith {
  Map<String, Object?> broadcastWith();
}

abstract interface class BroadcastsWhen {
  bool broadcastWhen();
}
