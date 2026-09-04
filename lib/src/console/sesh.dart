import 'dart:io';

import '../foundation/application.dart';
import 'command.dart';
import 'commands/about_command.dart';
import 'commands/api_commands.dart';
import 'commands/channel_list_command.dart';
import 'commands/key_generate_command.dart';
import 'commands/make_channel_command.dart';
import 'commands/make_command_command.dart';
import 'commands/make_controller_command.dart';
import 'commands/make_event_command.dart';
import 'commands/make_listener_command.dart';
import 'commands/make_middleware_command.dart';
import 'commands/make_provider_command.dart';
import 'commands/make_request_command.dart';
import 'commands/route_list_command.dart';
import 'commands/serve_command.dart';

/// The console runner used by `bin/maat.dart`.
class Sesh {
  Sesh(this.app, {StringSink? out, StringSink? err, List<Command>? commands})
    : _out = out ?? stdout,
      _err = err ?? stderr {
    for (final c in [...builtIn(), ...?commands]) {
      register(c);
    }
  }

  final Application app;
  final StringSink _out;
  final StringSink _err;
  final Map<String, Command> _commands = {};

  List<Command> get commands =>
      _commands.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Framework commands. Later tasks add entries here.
  static List<Command> builtIn() => [
    AboutCommand(),
    ApiClientCommand(),
    ApiOpenApiCommand(),
    ChannelListCommand(),
    KeyGenerateCommand(),
    MakeChannelCommand(),
    MakeCommandCommand(),
    MakeControllerCommand(),
    MakeEventCommand(),
    MakeListenerCommand(),
    MakeMiddlewareCommand(),
    MakeProviderCommand(),
    MakeRequestCommand(),
    RouteListCommand(),
    ServeCommand(),
  ];

  void register(Command command) {
    command
      ..app = app
      ..out = _out
      ..err = _err;
    _commands[command.name] = command;
  }

  Future<int> run(List<String> args) async {
    if (args.isEmpty || args.first == 'list') {
      _list();
      return 0;
    }
    if (args.first == 'help') {
      final target = args.length > 1 ? _commands[args[1]] : null;
      if (target == null) {
        _list();
        return 0;
      }
      _out.writeln('Description:\n  ${target.description}\n');
      _out.writeln(
        'Usage:\n  ${target.name} ${target.parsedSignature.usage()}',
      );
      return 0;
    }
    final command = _commands[args.first];
    if (command == null) {
      _err.writeln('Command "${args.first}" is not defined.');
      return 1;
    }
    try {
      command.bind(args.skip(1).toList());
    } on FormatException catch (e) {
      _err.writeln(e.message);
      _err.writeln('Usage: ${command.name} ${command.parsedSignature.usage()}');
      return 1;
    }
    return command.handle();
  }

  void _list() {
    _out.writeln('Maat\n\nAvailable commands:');
    final grouped = <String, List<Command>>{};
    for (final c in commands) {
      final ns = c.name.contains(':') ? c.name.split(':').first : '';
      grouped.putIfAbsent(ns, () => []).add(c);
    }
    final width =
        commands.fold<int>(0, (w, c) => c.name.length > w ? c.name.length : w) +
        2;
    for (final ns in grouped.keys.toList()..sort()) {
      if (ns.isNotEmpty) {
        _out.writeln(' $ns');
      }
      for (final c in grouped[ns]!) {
        _out.writeln('  ${c.name.padRight(width)}${c.description}');
      }
    }
  }
}
