import 'package:maat/src/api/rule_schema.dart';
import 'package:maat/src/api/schema.dart';
import 'package:test/test.dart';

ApiSchema field(String rules) =>
    rulesToSchema({'value': rules}).properties!['value']!;

void main() {
  group('type rules', () {
    test('integer, numeric, boolean and array map to their JSON types', () {
      expect(field('integer').type, ApiType.integer);
      expect(field('numeric').type, ApiType.number);
      expect(field('boolean').type, ApiType.boolean);
      expect(field('array').type, ApiType.array);
      expect(field('string').type, ApiType.string);
    });

    test('a rule set with constraints but no type rule is a string', () {
      // `sizeOf` measures a non-numeric value by its length, so this is what
      // the validator will actually enforce.
      final schema = field('required|max:120');
      expect(schema.type, ApiType.string);
      expect(schema.maxLength, 120);
    });

    test('a rule set with only control rules describes nothing', () {
      expect(field('required').type, ApiType.any);
      expect(field('sometimes|nullable').type, ApiType.any);
    });

    test('email, url, uuid and date carry a format', () {
      expect(field('email').format, 'email');
      expect(field('url').format, 'uri');
      expect(field('uuid').format, 'uuid');
      expect(field('date').format, 'date-time');
      expect(field('string').format, isNull);
    });
  });

  group('constraints', () {
    test('min and max are lengths on a string and bounds on a number', () {
      expect(field('string|min:1|max:5').minLength, 1);
      expect(field('string|min:1|max:5').maxLength, 5);
      expect(field('string|min:1|max:5').minimum, isNull);
      expect(field('integer|min:1|max:5').minimum, 1);
      expect(field('integer|min:1|max:5').maximum, 5);
      expect(field('integer|min:1|max:5').maxLength, isNull);
    });

    test('between and size fill both bounds', () {
      expect(field('integer|between:2,8').minimum, 2);
      expect(field('integer|between:2,8').maximum, 8);
      expect(field('string|size:4').minLength, 4);
      expect(field('string|size:4').maxLength, 4);
    });

    test('in becomes an enum', () {
      expect(field('string|in:draft,published').values, ['draft', 'published']);
      expect(field('integer|in:1,2').values, [1, 2]);
      expect(field('numeric|in:1,2.5').values, [1, 2.5]);
      expect(field('boolean|in:true,0').values, [true, false]);
    });

    test('regex becomes a pattern and is never split on commas', () {
      expect(field(r'regex:^a{2,3}$').pattern, r'^a{2,3}$');
    });

    test('digits constrain length and shape', () {
      expect(field('digits:4').minLength, 4);
      expect(field('digits:4').maxLength, 4);
      expect(field('digits:4').pattern, r'^\d+$');
      expect(field('digits_between:2,5').minLength, 2);
      expect(field('digits_between:2,5').maxLength, 5);
    });

    test('min and max on an array are item counts', () {
      final schema = rulesToSchema({
        'tags': 'array|min:1|max:3',
        'tags.*': 'string',
      }).properties!['tags']!;
      expect(schema.type, ApiType.array);
      expect(schema.minItems, 1);
      expect(schema.maxItems, 3);
    });
  });

  group('presence', () {
    test('required is neither optional nor nullable', () {
      expect(field('required|string').isOptional, isFalse);
      expect(field('required|string').isNullable, isFalse);
    });

    test('a field without required is optional', () {
      expect(field('string').isOptional, isTrue);
    });

    test('sometimes is optional even alongside required', () {
      // `sometimes|required` means "if it is here it must be filled", which
      // is an optional key holding a required value.
      expect(field('sometimes|required|string').isOptional, isTrue);
    });

    test('nullable and optional are tracked separately', () {
      final schema = field('required|nullable|integer');
      expect(schema.isNullable, isTrue);
      expect(schema.isOptional, isFalse);
      expect(schema.isDartNullable, isTrue);
    });
  });

  group('nesting', () {
    test('dotted keys build nested objects', () {
      final schema = rulesToSchema({
        'author.name': 'required|string',
        'author.email': 'required|email',
      });
      final author = schema.properties!['author']!;
      expect(author.type, ApiType.object);
      expect(author.properties!.keys, ['name', 'email']);
      expect(author.properties!['email']!.format, 'email');
    });

    test('a wildcard key makes an array of its items', () {
      final schema = rulesToSchema({'tags.*': 'required|string'});
      final tags = schema.properties!['tags']!;
      expect(tags.type, ApiType.array);
      expect(tags.items!.type, ApiType.string);
    });

    test('an array item is non-nullable without a nullable rule', () {
      final tags = rulesToSchema({
        'tags': 'array',
        'tags.*': 'string',
      }).properties!['tags']!;

      expect(tags.items!.isDartNullable, isFalse);
    });

    test('a wildcard segment nests objects inside the array', () {
      final schema = rulesToSchema({
        'items.*.sku': 'required|string',
        'items.*.qty': 'required|integer|min:1',
      });
      final items = schema.properties!['items']!;
      expect(items.type, ApiType.array);
      expect(items.items!.properties!['qty']!.type, ApiType.integer);
      expect(items.items!.properties!['qty']!.minimum, 1);
    });

    test('a node carries its own rules alongside its children', () {
      final schema = rulesToSchema({
        'author': 'required',
        'author.name': 'required|string',
      });
      final author = schema.properties!['author']!;
      expect(author.type, ApiType.object);
      expect(author.isOptional, isFalse);
    });

    test('a required child also requires its parent object', () {
      final author = rulesToSchema({
        'author.name': 'required|string',
      }).properties!['author']!;

      expect(author.isOptional, isFalse);
    });

    test('present requires a key without requiring a non-empty value', () {
      expect(field('present|nullable|string').isOptional, isFalse);
    });

    test('a top-level wildcard describes a list body', () {
      final schema = rulesToSchema({'*': 'required|integer'});
      expect(schema.type, ApiType.array);
      expect(schema.items!.type, ApiType.integer);
    });
  });

  test('unknown rules are ignored rather than throwing', () {
    expect(field('string|exists:books,id').type, ApiType.string);
  });

  test('the root object takes the given name and is never optional', () {
    final schema = rulesToSchema({'title': 'required|string'}, name: 'Book');
    expect(schema.name, 'Book');
    expect(schema.isOptional, isFalse);
  });
}
