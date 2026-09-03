import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => Config.current = Config({}));

  test('a hash verifies against its own password and nothing else', () {
    final hashed = Hash.make('correct horse');
    expect(hashed, startsWith(r'$argon2id$'));
    expect(Hash.check('correct horse', hashed), isTrue);
    expect(Hash.check('Correct horse', hashed), isFalse);
    expect(Hash.check('', hashed), isFalse);
  });

  test('the same password hashes differently every time', () {
    // A per-hash random salt, or two users with the same password would
    // be visibly identical in the table.
    expect(Hash.make('same'), isNot(Hash.make('same')));
  });

  test('a malformed hash is false, never an exception', () {
    // A truncated column value must not become a 500 — or an oracle that
    // tells an attacker which rows are corrupt.
    for (final bad in ['', 'not-a-hash', r'$argon2id$broken', r'$2y$10$x']) {
      expect(Hash.check('anything', bad), isFalse, reason: bad);
    }
  });

  test('needsRehash tracks the configured parameters', () {
    final hashed = Hash.make('secret');
    expect(Hash.needsRehash(hashed), isFalse);
    Config.current = Config({
      'hashing': {
        'argon': {'memory': 65536, 'time': 4, 'threads': 2},
      },
    });
    expect(Hash.needsRehash(hashed), isTrue);
    expect(Hash.check('secret', hashed), isTrue, reason: 'still verifies');
  });

  test('a malformed hash always needs rehashing', () {
    expect(Hash.needsRehash('garbage'), isTrue);
  });

  test('non-ASCII passwords keep their full value', () {
    // String.codeUnits is UTF-16 and argon2 takes bytes, so hashing the
    // units truncates every one above 255 to its low byte: U+0100 and
    // U+0000 collide, and an Arabic password loses a byte per character.
    // Verified against hashlib before this test was written.
    const arabic = 'كلمة السر';
    final hashed = Hash.make(arabic);
    expect(Hash.check(arabic, hashed), isTrue);
    expect(Hash.check('كلمة', hashed), isFalse);

    final wide = Hash.make(String.fromCharCode(0x0100));
    expect(Hash.check(String.fromCharCode(0x0000), wide), isFalse);
    expect(Hash.check(String.fromCharCode(0x0100), wide), isTrue);
  });

  test('async hashing does not block the request isolate', () async {
    final hashing = Hash.makeAsync('correct horse');
    final first = await Future.any([
      hashing.then((_) => 'hash'),
      Future.delayed(const Duration(milliseconds: 2), () => 'timer'),
    ]);

    expect(first, 'timer');
    final hashed = await hashing;
    expect(await Hash.checkAsync('correct horse', hashed), isTrue);
    expect(await Hash.checkAsync('wrong', hashed), isFalse);
  });
}
