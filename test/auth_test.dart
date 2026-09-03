import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Person implements Authenticatable {
  Person(this.id);
  final int id;
  @override
  Object get authIdentifier => id;
  @override
  String get authPassword => '';
}

class Other implements Authenticatable {
  @override
  Object get authIdentifier => 1;
  @override
  String get authPassword => '';
}

/// Authenticates when the request carries `x-who`.
class HeaderGuard implements Guard {
  @override
  Future<Authenticatable?> user(Request request) async {
    final who = request.header('x-who');
    return who == null ? null : Person(int.parse(who));
  }
}

void main() {
  setUp(() {
    Auth.reset();
    Config.current = Config({});
    Auth.extend('header', HeaderGuard.new);
  });
  tearDown(Auth.reset);

  Future<Response> run(Request request, {String? guard}) => Future.value(
    Authenticate(guard).handle(request, (r) {
      final user = r.user<Person>();
      return Response.text('id=${user?.id}');
    }),
  );

  test('a request the guard accepts reaches the handler with a user', () async {
    final request = Request.create(headers: {'x-who': '7'});
    final response = await run(request, guard: 'header');
    expect(response.encodedBody, 'id=7');
    expect(request.user<Person>()!.id, 7);
  });

  test('a request the guard rejects is 401 and never runs the handler', () {
    expect(
      () => run(Request.create(), guard: 'header'),
      throwsA(
        isA<UnauthorizedHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Unauthenticated.'),
      ),
    );
  });

  test('an unknown guard raises instead of letting the request through', () {
    // The important half: a typo in `auth:sanctm` must never be the same
    // as no middleware at all.
    expect(
      () => run(Request.create(headers: {'x-who': '7'}), guard: 'sanctm'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('no guard name falls back to the configured default', () async {
    Config.current = Config({
      'auth': {
        'defaults': {'guard': 'header'},
      },
    });
    final response = await run(Request.create(headers: {'x-who': '3'}));
    expect(response.encodedBody, 'id=3');
  });

  test('the alias factory reads the guard from the parameter', () async {
    final middleware = Authenticate.factory(['header']);
    final request = Request.create(headers: {'x-who': '5'});
    await middleware.handle(request, (r) => Response.text('ok'));
    expect(request.user<Person>()!.id, 5);
  });

  test('the guard runs once per request', () async {
    var calls = 0;
    Auth.reset();
    Auth.extend('counting', () => _CountingGuard(() => calls++));
    final request = Request.create();
    await Authenticate('counting').handle(request, (r) {
      r.user<Person>();
      r.user<Person>();
      return Response.text('ok');
    });
    expect(calls, 1);
  });

  group('typed access', () {
    test('user<T>() is null when nothing authenticated', () {
      expect(Request.create().user<Person>(), isNull);
    });

    test('requireUser<T>() throws rather than returning null', () {
      expect(
        () => Request.create().requireUser<Person>(),
        throwsA(isA<UnauthorizedHttpException>()),
      );
    });

    test('the wrong type is a clear error, not a silent null', () async {
      final request = Request.create();
      request.attributes[authUserAttribute] = Other();
      expect(
        () => request.user<Person>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Other'), contains('Person')),
          ),
        ),
      );
    });
  });
}

class _CountingGuard implements Guard {
  _CountingGuard(this.onCall);
  final void Function() onCall;
  @override
  Future<Authenticatable?> user(Request request) async {
    onCall();
    return Person(1);
  }
}
