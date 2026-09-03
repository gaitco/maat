import 'dart:io';

import 'package:args/args.dart';

import '../foundation/application.dart';
import 'signature.dart';

/// Base class for maat commands.
abstract class Command {
  String get name;
  String get description;
  String get signature => '';

  late final Application app;
  StringSink out = stdout;
  StringSink err = stderr;

  late Signature parsedSignature = Signature.parse(signature);
  ArgResults? _results;
  final Map<String, String?> _arguments = {};

  /// Bind parsed input. Throws [FormatException] on bad input.
  void bind(List<String> args) {
    final results = parsedSignature.buildParser().parse(args);
    final positional = results.rest;
    final defs = parsedSignature.arguments;
    final required = defs.where((a) => !a.optional).length;
    if (positional.length < required) {
      throw FormatException(
        'Not enough arguments (missing: ${defs.skip(positional.length).where((a) => !a.optional).map((a) => a.name).join(', ')}).',
      );
    }
    for (var i = 0; i < defs.length; i++) {
      _arguments[defs[i].name] = i < positional.length
          ? positional[i]
          : defs[i].defaultValue;
    }
    _results = results;
  }

  String? argument(String name) => _arguments[name];
  String? option(String name) => _results?[name] as String?;
  bool flag(String name) => _results?[name] == true;
  List<String> get rest =>
      _results?.rest.skip(parsedSignature.arguments.length).toList() ??
      const [];

  void info(String message) => out.writeln(message);
  void line(String message) => out.writeln(message);
  void warn(String message) => out.writeln('WARNING: $message');
  void error(String message) => err.writeln(message);

  void table(List<String> headers, List<List<String>> rows) {
    final widths = List<int>.generate(headers.length, (i) {
      var w = headers[i].length;
      for (final r in rows) {
        if (i < r.length && r[i].length > w) {
          w = r[i].length;
        }
      }
      return w;
    });
    String line(List<String> cells) => [
      for (var i = 0; i < headers.length; i++)
        (i < cells.length ? cells[i] : '').padRight(widths[i]),
    ].join('  ').trimRight();
    out.writeln(line(headers));
    out.writeln(line([for (final w in widths) '-' * w]));
    for (final r in rows) {
      out.writeln(line(r));
    }
  }

  Future<int> handle();
}
