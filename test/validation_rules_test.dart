import 'package:maat/maat.dart';
import 'package:test/test.dart';

bool ok(Map<String, dynamic> data, String rules, [String field = 'f']) =>
    Validator(data, {field: rules}).passes();

void main() {
  test('url', () {
    expect(ok({'f': 'https://a.b/c?x=1'}, 'url'), isTrue);
    expect(ok({'f': 'a.b'}, 'url'), isFalse);
    expect(ok({'f': 'ftp://x'}, 'url'), isFalse);
  });

  test('uuid', () {
    expect(ok({'f': '123e4567-e89b-12d3-a456-426614174000'}, 'uuid'), isTrue);
    expect(ok({'f': 'nope'}, 'uuid'), isFalse);
  });

  test('regex and not_regex keep colons and commas inside the pattern', () {
    expect(ok({'f': 'ab:1,2'}, r'regex:^[a-z]+:\d,\d$'), isTrue);
    expect(ok({'f': 'x'}, r'regex:^\d+$'), isFalse);
    expect(ok({'f': 'x'}, r'not_regex:^\d+$'), isTrue);
  });

  test('same and different compare to another field', () {
    expect(ok({'f': 'a', 'g': 'a'}, 'same:g'), isTrue);
    expect(ok({'f': 'a', 'g': 'b'}, 'same:g'), isFalse);
    expect(ok({'f': 'a', 'g': 'b'}, 'different:g'), isTrue);
    expect(Validator({'f': 'a', 'g': 'b'}, {'f': 'same:g'}).errors['f'], [
      'The f field must match g.',
    ]);
  });

  test('date, after, before with literals and fields', () {
    expect(ok({'f': '2026-09-02'}, 'date'), isTrue);
    expect(ok({'f': '2026-09-02T10:00:00Z'}, 'date'), isTrue);
    expect(ok({'f': 'tomorrow'}, 'date'), isFalse);
    expect(ok({'f': '2026-09-03'}, 'after:2026-09-02'), isTrue);
    expect(ok({'f': '2026-09-02'}, 'after:2026-09-02'), isFalse);
    expect(ok({'f': '2026-09-01'}, 'before:2026-09-02'), isTrue);
    expect(
      ok({'f': '2026-09-05', 'start': '2026-09-04'}, 'after:start'),
      isTrue,
    );
    expect(
      ok({'f': '2026-09-03', 'start': '2026-09-04'}, 'after:start'),
      isFalse,
    );
  });

  test('alpha, alpha_num, alpha_dash are unicode aware', () {
    expect(ok({'f': 'abcÉ'}, 'alpha'), isTrue);
    expect(ok({'f': 'محمد'}, 'alpha'), isTrue);
    expect(ok({'f': 'ab1'}, 'alpha'), isFalse);
    expect(ok({'f': 'ab1'}, 'alpha_num'), isTrue);
    expect(ok({'f': 'a-b_1'}, 'alpha_num'), isFalse);
    expect(ok({'f': 'a-b_1'}, 'alpha_dash'), isTrue);
    expect(ok({'f': 'a b'}, 'alpha_dash'), isFalse);
  });

  test('digits and digits_between', () {
    expect(ok({'f': '1234'}, 'digits:4'), isTrue);
    expect(ok({'f': 1234}, 'digits:4'), isTrue);
    expect(ok({'f': '123'}, 'digits:4'), isFalse);
    expect(ok({'f': '12a4'}, 'digits:4'), isFalse);
    expect(ok({'f': '123'}, 'digits_between:2,4'), isTrue);
    expect(ok({'f': '12345'}, 'digits_between:2,4'), isFalse);
  });

  test('starts_with and ends_with accept any of the params', () {
    expect(ok({'f': 'hello'}, 'starts_with:he,x'), isTrue);
    expect(ok({'f': 'hello'}, 'starts_with:x,y'), isFalse);
    expect(ok({'f': 'hello'}, 'ends_with:lo'), isTrue);
    expect(Validator({'f': 'hello'}, {'f': 'ends_with:x,y'}).errors['f'], [
      'The f field must end with one of the following: x, y.',
    ]);
  });

  test('required_if / required_unless', () {
    expect(
      ok({'type': 'company', 'f': ''}, 'required_if:type,company,corp'),
      isFalse,
    );
    expect(
      ok({'type': 'person', 'f': ''}, 'required_if:type,company,corp'),
      isTrue,
    );
    expect(
      ok({'type': 'person', 'f': ''}, 'required_unless:type,company'),
      isFalse,
    );
    expect(
      ok({'type': 'company', 'f': ''}, 'required_unless:type,company'),
      isTrue,
    );
    expect(
      Validator(
        {'type': 'company'},
        {'f': 'required_if:type,company'},
      ).errors['f'],
      ['The f field is required when type is company.'],
    );
  });

  test('required_with / required_without', () {
    expect(ok({'a': 1}, 'required_with:a,b'), isFalse);
    expect(ok({'a': ''}, 'required_with:a,b'), isTrue);
    expect(ok({}, 'required_without:a'), isFalse);
    expect(ok({'a': 1}, 'required_without:a'), isTrue);
    expect(Validator({'a': 1}, {'f': 'required_with:a,b'}).errors['f'], [
      'The f field is required when a, b is present.',
    ]);
  });
}
