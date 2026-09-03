import 'package:maat/maat.dart';
import 'package:test/test.dart';

class StorePostRequest extends FormRequest {
  StorePostRequest({this.allowed = true});
  final bool allowed;
  @override
  Map<String, Object> rules() => {
    'title': 'required|max:5',
    'body': 'required',
  };
  @override
  Map<String, String> messages() => {'body.required': 'Body please'};
  @override
  bool authorize(Request request) => allowed;
}

void main() {
  test('Validator.validate returns validated data or throws', () {
    expect(Validator({'a': 1, 'b': 2}, {'a': 'required'}).validate(), {'a': 1});
    expect(
      () => Validator({}, {'a': 'required'}).validate(),
      throwsA(
        isA<ValidationException>()
            .having((e) => e.errors, 'errors', {
              'a': ['The a field is required.'],
            })
            .having((e) => e.message, 'message', 'The given data was invalid.'),
      ),
    );
  });

  test('request.validate uses all() input', () async {
    final req = Request.create(path: '/?page=3', json: {'title': 'Hi'});
    expect(await req.validate({'title': 'required', 'page': 'integer'}), {
      'title': 'Hi',
      'page': '3',
    });
    await expectLater(
      req.validate({'nope': 'required'}),
      throwsA(isA<ValidationException>()),
    );
  });

  test('request.validateWith runs rules and custom messages', () async {
    final req = Request.create(json: {'title': 'toolong'});
    try {
      await req.validateWith(StorePostRequest());
      fail('should throw');
    } on ValidationException catch (e) {
      expect(e.errors, {
        'title': ['The title field must not be greater than 5 characters.'],
        'body': ['Body please'],
      });
    }
    expect(
      await Request.create(
        json: {'title': 'ok', 'body': 'b'},
      ).validateWith(StorePostRequest()),
      {'title': 'ok', 'body': 'b'},
    );
  });

  test('unauthorized form request throws 403', () async {
    await expectLater(
      Request.create(
        json: {'title': 'ok', 'body': 'b'},
      ).validateWith(StorePostRequest(allowed: false)),
      throwsA(
        isA<ForbiddenHttpException>().having(
          (e) => e.message,
          'message',
          'This action is unauthorized.',
        ),
      ),
    );
  });
}
