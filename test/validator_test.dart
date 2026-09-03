import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Uppercase implements Rule {
  @override
  bool passes(String attribute, dynamic value, Map<String, dynamic> data) =>
      value == value.toString().toUpperCase();
  @override
  String message() => 'The :attribute must be uppercase.';
}

void main() {
  // Validator.extend/extendAsync write into static registries, so a rule
  // registered by one test leaks into every other test in this file under
  // randomized ordering. Reset in setUp (not tearDown) so this also protects
  // against state left behind by a previous file's failed teardown.
  setUp(() => Validator.resetExtensions());

  test('passes and fails with laravel messages', () {
    final v = Validator({'name': ''}, {'name': 'required|string'});
    expect(v.fails(), isTrue);
    expect(v.errors, {
      'name': ['The name field is required.'],
    });
    expect(
      Validator({'name': 'x'}, {'name': 'required|string'}).passes(),
      isTrue,
    );
  });

  test('rules as list with Rule objects and custom messages/attributes', () {
    final v = Validator(
      {'code': 'abc', 'email': 'nope'},
      {
        'code': ['required', Uppercase()],
        'email': 'required|email',
      },
      messages: {'email.email': 'Bad email for :attribute'},
      attributes: {'email': 'e-mail address'},
    );
    expect(v.errors, {
      'code': ['The code must be uppercase.'],
      'email': ['Bad email for e-mail address'],
    });
  });

  test(
    'non-implicit rules skip absent and empty values; null runs unless nullable',
    () {
      expect(Validator({}, {'age': 'integer'}).passes(), isTrue);
      expect(Validator({'age': ''}, {'age': 'integer'}).passes(), isTrue);
      expect(Validator({'age': null}, {'age': 'integer'}).passes(), isFalse);
      expect(
        Validator({'age': null}, {'age': 'nullable|integer'}).passes(),
        isTrue,
      );
      expect(
        Validator({'age': 'x'}, {'age': 'nullable|integer'}).passes(),
        isFalse,
      );
    },
  );

  test('sometimes only validates when present', () {
    expect(
      Validator({}, {'age': 'sometimes|required|integer'}).passes(),
      isTrue,
    );
    expect(
      Validator({'age': ''}, {'age': 'sometimes|required|integer'}).passes(),
      isFalse,
    );
  });

  test('bail stops at first failure, otherwise all messages collected', () {
    expect(
      Validator({'n': 'x'}, {'n': 'integer|min:3'}).errors['n'],
      hasLength(2),
    );
    expect(
      Validator({'n': 'x'}, {'n': 'bail|integer|min:3'}).errors['n'],
      hasLength(1),
    );
  });

  test('size rules pick numeric, string or array semantics', () {
    expect(Validator({'v': 5}, {'v': 'integer|min:3'}).passes(), isTrue);
    expect(Validator({'v': 2}, {'v': 'integer|min:3'}).errors['v'], [
      'The v field must be at least 3.',
    ]);
    expect(Validator({'v': 'ab'}, {'v': 'min:3'}).errors['v'], [
      'The v field must be at least 3 characters.',
    ]);
    expect(
      Validator(
        {
          'v': [1],
        },
        {'v': 'array|min:3'},
      ).errors['v'],
      ['The v field must have at least 3 items.'],
    );
    expect(Validator({'v': 'abcd'}, {'v': 'max:3'}).errors['v'], [
      'The v field must not be greater than 3 characters.',
    ]);
    expect(Validator({'v': 7}, {'v': 'numeric|between:1,5'}).errors['v'], [
      'The v field must be between 1 and 5.',
    ]);
    expect(Validator({'v': 'abc'}, {'v': 'size:3'}).passes(), isTrue);
    expect(Validator({'v': '12'}, {'v': 'numeric|size:12'}).passes(), isTrue);
  });

  test('wildcards expand over lists and report indexed keys', () {
    final v = Validator(
      {
        'items': [
          {'name': 'a'},
          {'name': ''},
          {},
        ],
      },
      {'items': 'required|array', 'items.*.name': 'required|string'},
    );
    expect(v.errors, {
      'items.1.name': ['The items.1.name field is required.'],
      'items.2.name': ['The items.2.name field is required.'],
    });
    expect(
      Validator({'items': 'notalist'}, {'items.*.name': 'required'}).passes(),
      isTrue,
    );
  });

  test('dot keys read nested maps', () {
    expect(
      Validator(
        {
          'user': {'name': 'x'},
        },
        {'user.name': 'required'},
      ).passes(),
      isTrue,
    );
    expect(Validator({'user': {}}, {'user.name': 'required'}).errors.keys, [
      'user.name',
    ]);
  });

  test('validated returns only keys with rules, nested and wildcard roots', () {
    final v = Validator(
      {
        'a': 1,
        'b': 2,
        'user': {'name': 'n', 'pw': 'p'},
        'tags': ['x'],
        'opt': null,
      },
      {
        'a': 'required',
        'user.name': 'required',
        'tags.*': 'string',
        'missing': 'sometimes|string',
        'opt': 'nullable',
      },
    );
    expect(v.validated(), {
      'a': 1,
      'user': {'name': 'n'},
      'tags': ['x'],
      'opt': null,
    });
  });

  test('in, not_in, confirmed, boolean, array, string', () {
    expect(Validator({'r': 'admin'}, {'r': 'in:admin,user'}).passes(), isTrue);
    expect(Validator({'r': 'x'}, {'r': 'in:admin,user'}).errors['r'], [
      'The selected r is invalid.',
    ]);
    expect(Validator({'r': 'x'}, {'r': 'not_in:x'}).passes(), isFalse);
    expect(
      Validator({'p': 'a', 'p_confirmation': 'a'}, {'p': 'confirmed'}).passes(),
      isTrue,
    );
    expect(
      Validator(
        {'p': 'a', 'p_confirmation': 'b'},
        {'p': 'confirmed'},
      ).errors['p'],
      ['The p field confirmation does not match.'],
    );
    expect(Validator({'b': 'true'}, {'b': 'boolean'}).passes(), isTrue);
    expect(Validator({'b': 'yes'}, {'b': 'boolean'}).passes(), isFalse);
    expect(
      Validator(
        {
          'a': {'k': 1},
        },
        {'a': 'array'},
      ).passes(),
      isTrue,
    );
    expect(Validator({'s': 1}, {'s': 'string'}).passes(), isFalse);
  });

  test('extend registers custom rules', () {
    Validator.extend(
      'even',
      (ctx) => (ctx.value as int).isEven,
      message: 'The :attribute must be even.',
    );
    expect(Validator({'n': 3}, {'n': 'even'}).errors['n'], [
      'The n must be even.',
    ]);
  });

  test('unknown rule fails fast', () {
    expect(
      () => Validator({'n': 3}, {'n': 'nope'}).passes(),
      throwsArgumentError,
    );
  });

  test('present requires the key to exist but allows empty', () {
    expect(Validator({}, {'k': 'present'}).passes(), isFalse);
    expect(Validator({'k': ''}, {'k': 'present'}).passes(), isTrue);
  });

  test(':values placeholder is not corrupted by :value replacement (F1)', () {
    Validator.extend(
      'required_with',
      (ctx) => ctx.present,
      message: 'The :attribute field is required when :values is present.',
    );
    final v = Validator(
      {'other': 'x'},
      {'field': 'required_with:other,second'},
    );
    expect(v.errors['field'], [
      'The field field is required when other, second is present.',
    ]);
  });

  test('validated guards against wildcard key starting with * (F3)', () {
    final v = Validator({'a': 1}, {'*': 'required'});
    expect(v.validated(), {'a': 1});
  });

  test('errors returns unmodifiable map and lists (F4)', () {
    final v = Validator({'name': ''}, {'name': 'required'});
    final errors1 = v.errors;
    expect(() => errors1['name']!.add('extra'), throwsUnsupportedError);
    expect(() => errors1['injected'] = ['x'], throwsUnsupportedError);
  });

  test('camelCase attributes are humanized via Str.snake (F5)', () {
    final v = Validator({'firstName': ''}, {'firstName': 'required'});
    expect(v.errors['firstName'], ['The first name field is required.']);
  });

  test('extend with custom rule overrides builtin (F6)', () {
    Validator.extend('required', (ctx) => false, message: 'Custom required.');
    final v = Validator({}, {'x': 'required'});
    expect(v.errors['x'], ['Custom required.']);
  });
}
