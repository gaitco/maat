import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../command.dart';

/// Runs a child process and restarts it when watched Dart/env files change.
class DevServer {
  DevServer({
    required Future<Process> Function() spawn,
    required List<String> watchPaths,
    this.debounce = const Duration(milliseconds: 300),
    void Function(String message)? log,
  }) : _spawn = spawn, // ignore: prefer_initializing_formals
       _watchPaths = watchPaths, // ignore: prefer_initializing_formals
       _log = log ?? print;

  final Future<Process> Function() _spawn;
  final List<String> _watchPaths;
  final Duration debounce;
  final void Function(String) _log;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  Process? _child;
  Timer? _timer;
  Future<void>? _pendingLaunch;
  int restarts = 0;
  bool _stopping = false;

  Future<void> start() async {
    await _launch();
    for (final path in _watchPaths) {
      final dirPath = FileSystemEntity.isDirectorySync(path)
          ? path
          : p.dirname(path);
      final onlyFile = FileSystemEntity.isDirectorySync(path)
          ? null
          : p.basename(path);
      if (!Directory(dirPath).existsSync()) {
        continue;
      }
      _subscriptions.add(
        Directory(dirPath).watch(recursive: onlyFile == null).listen((event) {
          final name = p.basename(event.path);
          if (onlyFile != null && name != onlyFile) {
            return;
          }
          if (onlyFile == null && !name.endsWith('.dart') && name != '.env') {
            return;
          }
          _scheduleRestart(event.path);
        }),
      );
    }
  }

  void _scheduleRestart(String changed) {
    _timer?.cancel();
    _timer = Timer(debounce, () async {
      _log('File changed: $changed. Restarting server...');
      restarts++;
      await _kill();
      await _launch();
    });
  }

  Future<void> _launch() {
    final future = _doLaunch();
    _pendingLaunch = future;
    return future.whenComplete(() {
      if (identical(_pendingLaunch, future)) {
        _pendingLaunch = null;
      }
    });
  }

  /// Spawns the child, unless [stop] started while the spawn was in flight —
  /// in that case the freshly spawned child is killed immediately instead of
  /// being stored, so it never survives as an orphan.
  Future<void> _doLaunch() async {
    final child = await _spawn();
    if (_stopping) {
      await _terminate(child);
      return;
    }
    _child = child;
    unawaited(
      child.exitCode.then((code) {
        if (!_stopping && identical(_child, child) && code != 0) {
          _log('Server exited with code $code. Waiting for changes...');
        }
      }),
    );
  }

  Future<void> _kill() async {
    final child = _child;
    if (child == null) {
      return;
    }
    _child = null;
    await _terminate(child);
  }

  Future<void> _terminate(Process child) async {
    child.kill(ProcessSignal.sigterm);
    await child.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        child.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  Future<void> stop() async {
    _stopping = true;
    _timer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    // Wait for any in-flight spawn to settle (and, per _doLaunch, be killed
    // if it lands after _stopping flips) before declaring the child dead.
    final pending = _pendingLaunch;
    if (pending != null) {
      await pending;
    }
    await _kill();
  }
}

class ServeCommand extends Command {
  @override
  String get name => 'serve';
  @override
  String get description => 'Serve the application and restart on file changes';
  @override
  String get signature => '{--host=127.0.0.1} {--port=8000} {--no-watch}';

  @override
  Future<int> handle() async {
    final host = option('host')!;
    final port = option('port')!;
    Future<Process> spawn() => Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart'],
      workingDirectory: app.basePath,
      environment: {'APP_HOST': host, 'APP_PORT': port},
      mode: ProcessStartMode.inheritStdio,
    );

    if (flag('no-watch')) {
      final child = await spawn();
      return child.exitCode;
    }

    final server = DevServer(
      spawn: spawn,
      watchPaths: [
        'lib',
        'config',
        'routes',
        'bootstrap',
        '.env',
      ].map(app.path).toList(),
      log: info,
    );
    info(
      'Maat development server: http://$host:$port (watching for changes, Ctrl+C to stop)',
    );
    await server.start();
    final done = Completer<int>();
    late StreamSubscription<ProcessSignal> sigint;
    sigint = ProcessSignal.sigint.watch().listen((_) async {
      await server.stop();
      await sigint.cancel();
      if (!done.isCompleted) {
        done.complete(0);
      }
    });
    return done.future;
  }
}
