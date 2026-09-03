import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('serve'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'DevServer restarts the child when a watched dart file changes',
    () async {
      final lib = Directory(p.join(dir.path, 'lib'))..createSync();
      var spawns = 0;
      final logs = <String>[];
      final server = DevServer(
        spawn: () async {
          spawns++;
          return Process.start('sleep', ['30']);
        },
        watchPaths: [lib.path, p.join(dir.path, '.env')],
        debounce: const Duration(milliseconds: 100),
        log: logs.add,
      );
      await server.start();
      expect(spawns, 1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(p.join(lib.path, 'a.dart')).writeAsStringSync('void main() {}');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(spawns, 2);
      expect(server.restarts, 1);
      File(p.join(lib.path, 'notes.txt')).writeAsStringSync('ignored');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(spawns, 2, reason: 'non-dart files are ignored');
      await server.stop();
      expect(logs.any((l) => l.contains('Restarting')), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'stop() kills a child spawned while a restart was still in flight',
    () async {
      final lib = Directory(p.join(dir.path, 'lib'))..createSync();
      final spawned = <Process>[];
      var spawnCount = 0;
      final server = DevServer(
        spawn: () async {
          spawnCount++;
          if (spawnCount == 2) {
            // Simulate a slow-to-start child (e.g. `dart run` warmup) so
            // stop() can race the in-flight second spawn.
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          final proc = await Process.start('sleep', ['30']);
          spawned.add(proc);
          return proc;
        },
        watchPaths: [lib.path],
        debounce: const Duration(milliseconds: 100),
        log: (_) {},
      );
      await server.start();
      expect(spawnCount, 1);

      File(p.join(lib.path, 'a.dart')).writeAsStringSync('void main() {}');

      // Poll (rather than sleep a fixed guess) until the restart has begun
      // the second spawn call, so this isn't tied to watch-event latency.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (spawnCount < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        spawnCount,
        2,
        reason: 'restart should have begun before the deadline',
      );

      // The second spawn is still inside its artificial delay: stop() now
      // races an in-flight launch.
      await server.stop();

      // Give the delayed second spawn time to actually finish, regardless
      // of how long stop() itself took.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(
        spawned,
        hasLength(2),
        reason: 'the racing restart should still have spawned a child',
      );

      final orphan = spawned[1];
      final exitCode = await orphan.exitCode.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => -999,
      );
      expect(
        exitCode,
        isNot(-999),
        reason: 'stop() must kill a child spawned while shutdown was in flight',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    '--no-watch spawns the server once and never restarts on a file change',
    () async {
      Directory(p.join(dir.path, 'bin')).createSync();
      File(p.join(dir.path, 'bin', 'server.dart')).writeAsStringSync('''
import 'dart:io';

Future<void> main() async {
  File('marker.log').writeAsStringSync(
    'spawn\\n',
    mode: FileMode.append,
    flush: true,
  );
  await Future<void>.delayed(const Duration(milliseconds: 1500));
}
''');
      final lib = Directory(p.join(dir.path, 'lib'))..createSync();
      final application = await Application.configure(
        basePath: dir.path,
        environment: {},
      ).create();
      final out = StringBuffer();
      final maat = Sesh(application, out: out);

      final run = maat.run(['serve', '--no-watch']);
      // Touch a watched path while the (only) child is still running. With
      // --no-watch, no watcher exists to react to this at all.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(p.join(lib.path, 'a.dart')).writeAsStringSync('void main() {}');

      final exitCode = await run.timeout(const Duration(seconds: 15));
      expect(exitCode, 0);

      final marker = File(p.join(dir.path, 'marker.log'));
      final spawns = marker.existsSync()
          ? marker.readAsLinesSync().where((l) => l.isNotEmpty).length
          : 0;
      expect(
        spawns,
        1,
        reason: '--no-watch must spawn exactly once and never restart',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('serve command is registered with host/port/no-watch options', () async {
    final application = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    final out = StringBuffer();
    final maat = Sesh(application, out: out);
    expect(maat.commands.map((c) => c.name), contains('serve'));
    final serve = maat.commands.firstWhere((c) => c.name == 'serve');
    expect(
      serve.parsedSignature.options.map((o) => o.name),
      containsAll(['host', 'port', 'no-watch']),
    );
    expect(
      serve.parsedSignature.options
          .firstWhere((o) => o.name == 'port')
          .defaultValue,
      '8000',
    );
  });
}
