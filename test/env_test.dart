import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Env.parse', () {
    test('parses key=value, quotes, comments, blank lines', () {
      final parsed = Env.parse('''
# comment
APP_NAME=Maat
APP_DEBUG = true

DB_PASS="pa ss#word"
SINGLE='it''s'
EMPTY=
TRAILING=value # trailing comment
export EXPORTED=yes
''');
      expect(parsed['APP_NAME'], 'Maat');
      expect(parsed['APP_DEBUG'], 'true');
      expect(parsed['DB_PASS'], 'pa ss#word');
      expect(parsed['SINGLE'], "it's");
      expect(parsed['EMPTY'], '');
      expect(parsed['TRAILING'], 'value');
      expect(parsed['EXPORTED'], 'yes');
      expect(parsed.containsKey('# comment'), isFalse);
    });
  });

  group('Env.load', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('env_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('loads file and lets process environment override', () {
      final file = File(p.join(dir.path, '.env'))
        ..writeAsStringSync('A=file\nB=file');
      final env = Env.load(file.path, environment: {'B': 'process'});
      expect(env.get('A'), 'file');
      expect(env.get('B'), 'process');
      expect(env.get('C'), isNull);
      expect(identical(Env.current, env), isTrue);
    });

    test('missing file yields only process environment', () {
      final env = Env.load(p.join(dir.path, 'nope'), environment: {'X': '1'});
      expect(env.get('X'), '1');
    });
  });

  group('helpers', () {
    setUp(
      () => Env.current = Env.fromMap({
        'S': 'x',
        'T': 'true',
        'F': '0',
        'N': '8080',
      }),
    );

    test('env returns value or default', () {
      expect(env('S'), 'x');
      expect(env('MISSING'), isNull);
      expect(env('MISSING', 'dflt'), 'dflt');
    });

    test('envBool parses true/1/yes/on', () {
      expect(envBool('T'), isTrue);
      expect(envBool('F'), isFalse);
      expect(envBool('MISSING', true), isTrue);
    });

    test('envInt parses or defaults', () {
      expect(envInt('N'), 8080);
      expect(envInt('S', 5), 5);
      expect(envInt('MISSING', 7), 7);
    });
  });
}
