import 'dart:async';
import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class Auth extends Middleware {
  @override
  FutureOr<Response> handle(Request request, Next next) => next(request);
}

void main() {
  late Directory dir;
  late StringBuffer out;
  late Sesh maat;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('info');
    File(
      p.join(dir.path, '.env'),
    ).writeAsStringSync('APP_NAME=Demo\nAPP_KEY=\nOTHER=1\n');
    final application =
        await Application.configure(basePath: dir.path, environment: {})
            .withConfig({
              'app': {'name': env('APP_NAME'), 'debug': true},
            })
            .withMiddleware((m) => m.alias({'auth': Auth()}))
            .create();
    Route.get(
      '/users/{id}',
      (Request r) => 1,
    ).name('users.show').middleware(['auth']);
    Route.post('/users', (Request r) => 1).middleware([Auth()]);
    out = StringBuffer();
    maat = Sesh(application, out: out);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('route:list prints a table', () async {
    expect(await maat.run(['route:list']), 0);
    final text = out.toString();
    expect(text, contains('Method'));
    expect(text, matches(RegExp(r'GET\s+/users/\{id\}\s+users\.show\s+auth')));
    expect(text, matches(RegExp(r'POST\s+/users\s+Auth')));
    expect(text, isNot(contains('HEAD')));
  });

  test('key:generate writes APP_KEY into .env and keeps other lines', () async {
    expect(await maat.run(['key:generate']), 0);
    final env = File(p.join(dir.path, '.env')).readAsStringSync();
    expect(env, matches(RegExp(r'APP_KEY=base64:[A-Za-z0-9+/=]{44}')));
    expect(env, contains('APP_NAME=Demo'));
    expect(env, contains('OTHER=1'));
    expect(out.toString(), contains('Application key set successfully.'));
  });

  test('key:generate --show only prints', () async {
    await maat.run(['key:generate', '--show']);
    expect(
      out.toString().trim(),
      matches(RegExp(r'^base64:[A-Za-z0-9+/=]{44}$')),
    );
    expect(
      File(p.join(dir.path, '.env')).readAsStringSync(),
      contains('APP_KEY=\n'),
    );
  });

  test('about prints environment details', () async {
    await maat.run(['about']);
    final text = out.toString();
    expect(text, contains('Application Name'));
    expect(text, contains('Demo'));
    expect(text, contains('Maat Version'));
    expect(text, contains(Application.version));
    expect(text, contains('Dart Version'));
  });
}
