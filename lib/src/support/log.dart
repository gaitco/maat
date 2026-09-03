import 'dart:io';

/// Single-channel logger: stdout plus an optional file.
// ponytail: one channel; add drivers/channels in Phase 4 if a real need appears.
abstract final class Log {
  static StringSink sink = stdout;
  static String? filePath;
  static String environment = 'production';

  static void debug(Object message, [Object? error, StackTrace? stackTrace]) =>
      _write('DEBUG', message, error, stackTrace);
  static void info(Object message, [Object? error, StackTrace? stackTrace]) =>
      _write('INFO', message, error, stackTrace);
  static void warning(
    Object message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _write('WARNING', message, error, stackTrace);
  static void error(Object message, [Object? error, StackTrace? stackTrace]) =>
      _write('ERROR', message, error, stackTrace);

  static void _write(
    String level,
    Object message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final buffer = StringBuffer(
      '[${_timestamp()}] $environment.$level: $message',
    );
    if (error != null) buffer.write(' | $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    final line = '$buffer\n';
    sink.write(line);
    final path = filePath;
    if (path != null) {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    }
  }

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
}
