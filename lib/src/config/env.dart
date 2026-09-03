import 'dart:io';

/// Environment variables from `.env` merged with the process environment.
class Env {
  Env.fromMap(Map<String, String> values) : _values = Map.unmodifiable(values);

  /// The active environment. Set by [load] and by `Application.configure`.
  static Env current = Env.fromMap({});

  final Map<String, String> _values;

  Map<String, String> get all => _values;
  String? get(String key) => _values[key];
  bool has(String key) => _values.containsKey(key);

  /// Load [filePath] if it exists; the process [environment] wins on conflicts.
  static Env load(String filePath, {Map<String, String>? environment}) {
    final file = File(filePath);
    final fromFile = file.existsSync()
        ? parse(file.readAsStringSync())
        : <String, String>{};
    final env = Env.fromMap({
      ...fromFile,
      ...(environment ?? Platform.environment),
    });
    current = env;
    return env;
  }

  /// Parse dotenv syntax: `KEY=value`, optional `export`, quotes, `#` comments.
  static Map<String, String> parse(String contents) {
    final result = <String, String>{};
    for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 && (value.startsWith('"') && value.endsWith('"'))) {
        value = value.substring(1, value.length - 1).replaceAll(r'\n', '\n');
      } else if (value.length >= 2 &&
          value.startsWith("'") &&
          value.endsWith("'")) {
        value = value.substring(1, value.length - 1).replaceAll("''", "'");
      } else {
        final hash = value.indexOf(' #');
        if (hash >= 0) value = value.substring(0, hash).trim();
      }
      result[key] = value;
    }
    return result;
  }
}

String? env(String key, [String? defaultValue]) =>
    Env.current.get(key) ?? defaultValue;

bool envBool(String key, [bool defaultValue = false]) {
  final v = Env.current.get(key)?.toLowerCase();
  if (v == null) return defaultValue;
  return const {'true', '1', 'yes', 'on'}.contains(v);
}

int envInt(String key, [int defaultValue = 0]) =>
    int.tryParse(Env.current.get(key) ?? '') ?? defaultValue;
