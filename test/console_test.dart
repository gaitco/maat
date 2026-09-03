import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Greet extends Command {
  @override
  String get name => 'app:greet';
  @override
  String get description => 'Greets someone';
  @override
  String get signature => '{name} {title?} {--shout} {--times=1} {--s|suffix=}';

  @override
  Future<int> handle() async {
    var msg =
        'Hello ${argument('name')}${argument('title') == null ? '' : ' the ${argument('title')}'}';
    if (flag('shout')) msg = msg.toUpperCase();
    final suffix = option('suffix');
    if (suffix != null) msg += suffix;
    for (var i = 0; i < int.parse(option('times')!); i++) {
      info(msg);
    }
    return 0;
  }
}

class Fail extends Command {
  @override
  String get name => 'app:fail';
  @override
  String get description => 'Always fails';
  @override
  Future<int> handle() async {
    error('nope');
    return 3;
  }
}

void main() {
  group('Signature.parse', () {
    test('arguments and options', () {
      final s = Signature.parse(
        '{name} {title?} {mode=fast} {--shout} {--times=1} {--s|suffix=} {--no-watch}',
      );
      expect(s.arguments.map((a) => a.name), ['name', 'title', 'mode']);
      expect(s.arguments[0].optional, isFalse);
      expect(s.arguments[1].optional, isTrue);
      expect(s.arguments[2].defaultValue, 'fast');
      expect(s.options.map((o) => o.name), [
        'shout',
        'times',
        'suffix',
        'no-watch',
      ]);
      expect(s.options[0].isFlag, isTrue);
      expect(s.options[1].defaultValue, '1');
      expect(s.options[2].isFlag, isFalse);
      expect(s.options[2].abbr, 's');
    });
  });

  group('Sesh', () {
    late Directory dir;
    late Application application;
    late StringBuffer out;
    late StringBuffer err;
    late Sesh maat;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('console');
      application = await Application.configure(
        basePath: dir.path,
        environment: {},
      ).create();
      out = StringBuffer();
      err = StringBuffer();
      maat = Sesh(application, out: out, err: err, commands: [Greet(), Fail()]);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('runs a command with arguments, flags and options', () async {
      final code = await maat.run([
        'app:greet',
        'Ada',
        'Great',
        '--shout',
        '--times=2',
        '-s',
        '!',
      ]);
      expect(code, 0);
      expect(out.toString(), 'HELLO ADA THE GREAT!\nHELLO ADA THE GREAT!\n');
    });

    test('optional argument may be omitted', () async {
      await maat.run(['app:greet', 'Ada']);
      expect(out.toString(), 'Hello Ada\n');
    });

    test('missing required argument prints usage and returns 1', () async {
      expect(await maat.run(['app:greet']), 1);
      expect(err.toString(), contains('Not enough arguments'));
      expect(err.toString(), contains('app:greet {name} {title?}'));
    });

    test('list groups commands by namespace', () async {
      expect(await maat.run([]), 0);
      final text = out.toString();
      expect(text, contains('app'));
      expect(text, contains('app:greet'));
      expect(text, contains('Greets someone'));
      expect(text.indexOf('app:fail'), lessThan(text.indexOf('app:greet')));
    });

    test('help shows usage', () async {
      expect(await maat.run(['help', 'app:greet']), 0);
      expect(out.toString(), contains('Usage:'));
      expect(out.toString(), contains('--shout'));
    });

    test('unknown command and exit codes', () async {
      expect(await maat.run(['nope']), 1);
      expect(err.toString(), contains('Command "nope" is not defined'));
      expect(await maat.run(['app:fail']), 3);
      expect(err.toString(), contains('nope'));
    });

    test(
      'command has access to the app and table renders aligned columns',
      () async {
        final cmd = Greet();
        maat.register(cmd);
        await maat.run(['app:greet', 'x']);
        expect(identical(cmd.app, application), isTrue);
        out.clear();
        cmd.table(
          ['Method', 'URI'],
          [
            ['GET', '/a'],
            ['DELETE', '/long/path'],
          ],
        );
        expect(
          out.toString(),
          'Method  URI\n------  ----------\nGET     /a\nDELETE  /long/path\n',
        );
      },
    );
  });
}
