import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late StringBuffer buffer;
  setUp(() {
    buffer = StringBuffer();
    Log.sink = buffer;
    Log.filePath = null;
    Log.environment = 'testing';
  });

  test('writes level, env and message', () {
    Log.info('hello');
    expect(
      buffer.toString(),
      matches(
        r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] testing\.INFO: hello\n$',
      ),
    );
  });

  test('error includes error and stack', () {
    Log.error('boom', StateError('bad'), StackTrace.current);
    final out = buffer.toString();
    expect(out, contains('testing.ERROR: boom'));
    expect(out, contains('Bad state: bad'));
    expect(out, contains('log_test.dart'));
  });

  test('appends to file when filePath set', () {
    final dir = Directory.systemTemp.createTempSync('log');
    addTearDown(() => dir.deleteSync(recursive: true));
    Log.filePath = p.join(dir.path, 'nested', 'app.log');
    Log.warning('w1');
    Log.warning('w2');
    final lines = File(Log.filePath!).readAsLinesSync();
    expect(lines, hasLength(2));
    expect(lines.first, contains('testing.WARNING: w1'));
  });
}
