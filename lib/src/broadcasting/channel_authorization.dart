import 'dart:async';

import '../auth/authenticatable.dart';

typedef ChannelAuthorizer =
    FutureOr<Object?> Function(
      Authenticatable user,
      Map<String, String> params,
    );

class ChannelAuthorizationRegistry {
  final List<_ChannelRegistration> _registrations = [];

  List<String> get patterns => List.unmodifiable(
    _registrations.map((registration) => registration.pattern),
  );

  void channel(String pattern, ChannelAuthorizer authorizer) {
    final names = <String>[];
    final source = StringBuffer('^');
    var offset = 0;
    for (final match in RegExp(r'\{(\w+)\}').allMatches(pattern)) {
      source
        ..write(RegExp.escape(pattern.substring(offset, match.start)))
        ..write(r'([^/\.]+)');
      names.add(match.group(1)!);
      offset = match.end;
    }
    source
      ..write(RegExp.escape(pattern.substring(offset)))
      ..write(r'$');
    _registrations.add(
      _ChannelRegistration(
        pattern,
        RegExp(source.toString()),
        names,
        authorizer,
      ),
    );
  }

  Future<Object?> authorize(String channelName, Authenticatable user) async {
    final name = channelName.startsWith('private-')
        ? channelName.substring('private-'.length)
        : channelName.startsWith('presence-')
        ? channelName.substring('presence-'.length)
        : channelName;
    for (final registration in _registrations) {
      final match = registration.expression.firstMatch(name);
      if (match == null) continue;
      return registration.authorizer(user, {
        for (var index = 0; index < registration.names.length; index++)
          registration.names[index]: match.group(index + 1)!,
      });
    }
    return null;
  }
}

class _ChannelRegistration {
  _ChannelRegistration(
    this.pattern,
    this.expression,
    this.names,
    this.authorizer,
  );

  final String pattern;
  final RegExp expression;
  final List<String> names;
  final ChannelAuthorizer authorizer;
}
