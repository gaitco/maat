import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:hashlib/hashlib.dart';

import '../config/config.dart';

/// Password hashing. Laravel's `Hash` facade.
///
/// argon2id, because a password is low-entropy and an attacker holding
/// the table will try billions of guesses: verification is meant to be
/// slow. API tokens are the opposite case and are hashed with SHA-256 —
/// see `cartouche`.
abstract final class Hash {
  /// 16 bytes, the argon2 specification's recommendation and what every
  /// other implementation emits: a salt only has to be unique, and a
  /// shorter one starts colliding across a large user table.
  static const _saltBytes = 16;

  /// OWASP's 2024 argon2id floor: 19 MiB, 2 iterations, 1 lane.
  static const _defaults = {'memory': 19456, 'time': 2, 'threads': 1};

  static Map<String, int> get _params {
    final configured = config('hashing.argon');
    if (configured is! Map) return Map.of(_defaults);
    return {
      for (final key in _defaults.keys)
        key: (configured[key] as int?) ?? _defaults[key]!,
    };
  }

  /// A PHC string: `$argon2id$v=19$m=…,t=…,p=…$<salt>$<hash>`. The
  /// parameters travel with the hash, so raising them later does not
  /// invalidate what is already stored.
  static String make(String plain) => _make(plain, _params);

  static String _make(String plain, Map<String, int> p) {
    final random = Random.secure();
    final salt = List<int>.generate(_saltBytes, (_) => random.nextInt(256));
    return argon2id(
      // utf8.encode, never String.codeUnits: those are UTF-16 units and
      // argon2 takes bytes, so every unit above 255 - the whole of
      // Arabic, CJK, and anything past Latin-1 - is truncated to its low
      // byte. U+0100 and U+0000 then hash identically, and two different
      // passwords can open the same account.
      utf8.encode(plain),
      salt,
      security: Argon2Security(
        'maat',
        m: p['memory']!,
        t: p['time']!,
        p: p['threads']!,
      ),
    ).encoded();
  }

  /// Hash on a worker isolate so request handling stays responsive.
  static Future<String> makeAsync(String plain) {
    final p = _params;
    // ponytail: one isolate per hash; use a fixed worker pool when measured
    // authentication throughput shows isolate startup is the bottleneck.
    return Isolate.run(() => _make(plain, p));
  }

  /// Verifies [plain] against [hashed], using the parameters [hashed]
  /// carries rather than the current configuration.
  ///
  /// Returns false rather than throwing for anything unparseable: a
  /// corrupt row must be a failed login, not a 500 that tells an
  /// attacker which rows are corrupt.
  static bool check(String plain, String hashed) {
    if (hashed.isEmpty) return false;
    try {
      return argon2Verify(hashed, utf8.encode(plain));
    } catch (_) {
      return false;
    }
  }

  /// Verify on a worker isolate so request handling stays responsive.
  static Future<bool> checkAsync(String plain, String hashed) =>
      Isolate.run(() => check(plain, hashed));

  /// True when [hashed] was made with weaker parameters than the
  /// current configuration, so a successful login can upgrade it.
  /// Unparseable hashes always need rehashing.
  static bool needsRehash(String hashed) {
    final found = RegExp(r'\$m=(\d+),t=(\d+),p=(\d+)\$').firstMatch(hashed);
    if (found == null) return true;
    final p = _params;
    return int.parse(found.group(1)!) < p['memory']! ||
        int.parse(found.group(2)!) < p['time']! ||
        int.parse(found.group(3)!) < p['threads']!;
  }
}
