import 'package:args/args.dart';

class SignatureArgument {
  SignatureArgument(this.name, {this.optional = false, this.defaultValue});
  final String name;
  final bool optional;
  final String? defaultValue;
}

class SignatureOption {
  SignatureOption(
    this.name, {
    this.isFlag = false,
    this.defaultValue,
    this.abbr,
  });
  final String name;
  final bool isFlag;
  final String? defaultValue;
  final String? abbr;
}

/// Laravel's `{arg} {arg?} {arg=default} {--flag} {--opt=} {--opt=default} {--s|opt}` syntax.
class Signature {
  Signature(this.arguments, this.options);
  final List<SignatureArgument> arguments;
  final List<SignatureOption> options;

  static Signature parse(String signature) {
    final arguments = <SignatureArgument>[];
    final options = <SignatureOption>[];
    for (final m in RegExp(r'\{([^}]+)\}').allMatches(signature)) {
      final token = m[1]!.trim();
      if (token.startsWith('--')) {
        var body = token.substring(2);
        String? abbr;
        final pipe = body.indexOf('|');
        if (pipe > 0) {
          abbr = body.substring(0, pipe);
          body = body.substring(pipe + 1);
        }
        final eq = body.indexOf('=');
        if (eq < 0) {
          options.add(SignatureOption(body, isFlag: true, abbr: abbr));
        } else {
          final def = body.substring(eq + 1);
          options.add(
            SignatureOption(
              body.substring(0, eq),
              defaultValue: def.isEmpty ? null : def,
              abbr: abbr,
            ),
          );
        }
      } else if (token.endsWith('?')) {
        arguments.add(
          SignatureArgument(
            token.substring(0, token.length - 1),
            optional: true,
          ),
        );
      } else if (token.contains('=')) {
        final eq = token.indexOf('=');
        arguments.add(
          SignatureArgument(
            token.substring(0, eq),
            optional: true,
            defaultValue: token.substring(eq + 1),
          ),
        );
      } else {
        arguments.add(SignatureArgument(token));
      }
    }
    return Signature(arguments, options);
  }

  ArgParser buildParser() {
    final parser = ArgParser();
    for (final o in options) {
      if (o.isFlag) {
        parser.addFlag(o.name, abbr: o.abbr, negatable: false);
      } else {
        parser.addOption(o.name, abbr: o.abbr, defaultsTo: o.defaultValue);
      }
    }
    return parser;
  }

  String usage() {
    final args = arguments.map(
      (a) => a.optional ? '{${a.name}?}' : '{${a.name}}',
    );
    final opts = options.map(
      (o) =>
          o.isFlag ? '[--${o.name}]' : '[--${o.name}=${o.defaultValue ?? ''}]',
    );
    return [...args, ...opts].join(' ');
  }
}
