import 'package:maat/maat.dart';
import 'package:test/test.dart';

/// Registered fresh whenever a test resets the static registries.
void registerFixtures() {
  Validator.extendAsync(
    'even_async',
    (ctx) async => (int.tryParse('${ctx.value}') ?? 1) % 2 == 0,
    message: 'The :attribute must be even.',
  );
  Validator.extendAsync(
    'in_async',
    (ctx) async => ctx.params.contains('${ctx.value}'),
    message: 'The :attribute is not in :values.',
  );
  Validator.extendAsync(
    'boom_async',
    (ctx) async => throw StateError('the round-trip failed'),
  );
}

void main() {
  setUpAll(registerFixtures);

  test('validateAsync runs an async rule', () async {
    final v = Validator.make({'n': '4'}, {'n': 'required|even_async'});
    expect(await v.passesAsync(), isTrue);

    final bad = Validator.make({'n': '3'}, {'n': 'required|even_async'});
    expect(await bad.passesAsync(), isFalse);
    expect(bad.errors['n']!.single, 'The n must be even.');
  });

  test('validateAsync returns only the validated keys', () async {
    final v = Validator.make(
      {'n': '4', 'extra': 'x'},
      {'n': 'required|even_async'},
    );
    expect(await v.validateAsync(), {'n': '4'});
  });

  test('the sync path throws a named error when an async rule is present', () {
    final v = Validator.make({'n': '4'}, {'n': 'required|even_async'});

    expect(
      () => v.passes(),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('even_async'))
            .having((e) => e.message, 'message', contains('passesAsync')),
      ),
    );
  });

  test('the sync path still works with no async rule', () {
    expect(
      Validator.make({'n': '4'}, {'n': 'required|integer'}).passes(),
      isTrue,
    );
  });

  test(
    'two rules of the same name on one attribute keep separate verdicts',
    () async {
      // 'a' satisfies the first list and not the second, so order must not
      // change the verdict and neither occurrence may read the other's slot.
      for (final rules in [
        'in_async:a,b|in_async:b,c',
        'in_async:b,c|in_async:a,b',
      ]) {
        final v = Validator.make({'x': 'a'}, {'x': rules});
        expect(await v.passesAsync(), isFalse, reason: rules);
        expect(v.errors['x']!.single, 'The x is not in b, c.', reason: rules);
      }

      expect(
        await Validator.make(
          {'x': 'b'},
          {'x': 'in_async:a,b|in_async:b,c'},
        ).passesAsync(),
        isTrue,
      );
    },
  );

  test('an async rule behind a bail never reports its failure', () async {
    final v = Validator.make({'n': 'x'}, {'n': 'bail|integer|boom_async'});
    expect(await v.passesAsync(), isFalse);
    expect(v.errors['n']!.single, contains('integer'));
  });

  test('an async rule the loop reaches still throws', () async {
    await expectLater(
      Validator.make({'n': '1'}, {'n': 'integer|boom_async'}).passesAsync(),
      throwsA(isA<StateError>()),
    );
  });

  test('an async rule runs per wildcard element', () async {
    final v = Validator.make(
      {
        'rows': [
          {'n': '4'},
          {'n': '3'},
        ],
      },
      {'rows.*.n': 'even_async'},
    );
    expect(await v.passesAsync(), isFalse);
    expect(v.errors.keys, ['rows.1.n']);
  });

  group('registration', () {
    tearDown(() {
      Validator.resetExtensions();
      registerFixtures();
    });

    test('extendAsync refuses a name a sync rule already owns', () {
      Validator.extend('collide', (ctx) => true, implicit: true);
      expect(
        () => Validator.extendAsync('collide', (ctx) async => true),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('collide'),
          ),
        ),
      );
    });

    test('extendAsync refuses an implicit or control rule name', () {
      for (final name in ['required', 'nullable', 'bail']) {
        expect(
          () => Validator.extendAsync(name, (ctx) async => true),
          throwsA(isA<ArgumentError>()),
          reason: name,
        );
      }
    });

    test('extend refuses a name an async rule already owns', () {
      expect(
        () => Validator.extend('even_async', (ctx) => true),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resetExtensions forgets both registries', () {
      Validator.resetExtensions();
      expect(
        () => Validator.make({'n': '4'}, {'n': 'even_async'}).passes(),
        throwsA(isA<ArgumentError>()),
      );
      // Freed, so the name is registrable again on the other side.
      Validator.extend('even_async', (ctx) => true);
    });
  });
}
