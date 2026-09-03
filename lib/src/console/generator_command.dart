import 'dart:io';

import 'package:path/path.dart' as p;

import '../support/str.dart';
import 'command.dart';

/// Shared behaviour for `make:*`: derive class name and path, write the stub once.
abstract class GeneratorCommand extends Command with GeneratesFiles {
  /// Human label, e.g. `Controller`.
  String get type;

  /// Directory relative to the app root, e.g. `lib/app/http/controllers`.
  String get directory;

  String stub(String className);

  @override
  String get signature => '{name} {--force}';

  @override
  Future<int> handle() async {
    final raw = argument('name')!.replaceAll(RegExp(r'\.dart$'), '');
    final parts = raw.split(RegExp(r'[/\\]'));
    final className = Str.studly(parts.last);
    final subdirs = parts.take(parts.length - 1).map(Str.snake);
    final relative = p.joinAll([
      directory,
      ...subdirs,
      '${Str.snake(className)}.dart',
    ]);
    final file = File(app.path(relative));
    if (file.existsSync() && !flag('force')) {
      error('$type [$relative] already exists. Use --force to overwrite.');
      return 1;
    }
    writeGenerated(relative, stub(className));
    info('$type [$relative] created successfully.');
    return 0;
  }
}

/// `writeGenerated`, factored out of [GeneratorCommand] so a command that
/// can't extend it — [MakeMigrationCommand] in `maat_seshat`, which
/// needs `Command`'s bare `handle` because it writes two generated files
/// (the migration stub and the rewritten registry) rather than one — can
/// still route every generated file through the same formatting step.
mixin GeneratesFiles on Command {
  /// Writes [contents] to the application-relative [relative], then hands the
  /// file to `dart format`.
  ///
  /// Stubs are written as plain readable Dart. Where the lines break is the
  /// formatter's business and cannot be baked into a stub: the shape
  /// `dart format` picks depends on how long the generated names are, so a
  /// hand-formatted stub is only correct for names close to the one it was
  /// written against.
  ///
  /// A formatting failure is a warning, never an error. The file on disk is
  /// valid Dart, merely untidy, and throwing away a generated file over a
  /// cosmetic step would be the worse outcome.
  void writeGenerated(String relative, String contents) {
    final file = File(app.path(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    final failure = _formatFailure(file.path);
    if (failure != null) {
      warn('[$relative] was written but `dart format` failed: $failure');
    }
  }

  /// Formats [path] in place, returning null on success or why it failed.
  static String? _formatFailure(String path) {
    // The SDK running maat is the one to format with — except when
    // maat has been compiled ahead of time, where the running executable
    // is the app itself and `dart` has to come from PATH.
    final executable = Platform.resolvedExecutable;
    final dart = p.basenameWithoutExtension(executable) == 'dart'
        ? executable
        : 'dart';
    try {
      final result = Process.runSync(dart, ['format', path]);
      if (result.exitCode == 0) return null;
      // First line only: a parse failure follows it with a source excerpt
      // drawn in box characters, which is noise in a one-line warning.
      final reason = '${result.stderr}'
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      return reason.isEmpty ? 'exit code ${result.exitCode}' : reason;
    } on ProcessException catch (e) {
      return e.message;
    }
  }
}
