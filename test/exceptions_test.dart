import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  test('HttpException defaults message to the reason phrase', () {
    expect(HttpException(404).message, 'Not Found');
    expect(HttpException(418, 'teapot').message, 'teapot');
  });

  test('subclasses carry fixed statuses and headers', () {
    expect(NotFoundHttpException().statusCode, 404);
    expect(UnauthorizedHttpException().statusCode, 401);
    expect(ForbiddenHttpException().statusCode, 403);
    expect(TooManyRequestsHttpException().statusCode, 429);
    final m = MethodNotAllowedHttpException(['GET', 'POST']);
    expect(m.statusCode, 405);
    expect(m.headers['allow'], 'GET, POST');
  });

  test('abort throws HttpException', () {
    expect(
      () => abort(403, 'nope'),
      throwsA(
        isA<HttpException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.message, 'msg', 'nope'),
      ),
    );
  });

  test('HttpResponseException wraps a response', () {
    final e = HttpResponseException(Response.text('x', status: 400));
    expect(e.response.statusCode, 400);
  });

  test('reasonPhrase', () {
    expect(reasonPhrase(422), 'Unprocessable Content');
    expect(reasonPhrase(599), 'Unknown Status');
  });
}
