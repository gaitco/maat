class Channel {
  const Channel(this.name);

  final String name;

  String get prefixedName => name;
}

class PrivateChannel extends Channel {
  const PrivateChannel(super.name);

  @override
  String get prefixedName =>
      name.startsWith('private-') ? name : 'private-$name';
}

class PresenceChannel extends Channel {
  const PresenceChannel(super.name);

  @override
  String get prefixedName =>
      name.startsWith('presence-') ? name : 'presence-$name';
}
