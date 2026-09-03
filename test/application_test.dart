import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final calls = <String>[];

class Greeter {
  Greeter(this.name);
  final String name;
}

class FirstProvider extends ServiceProvider {
  FirstProvider(super.app);
  @override
  void register() {
    calls.add('first.register');
    this.app.singleton<Greeter>((c) => Greeter(config('app.name')));
  }

  @override
  Future<void> boot() async {
    await Future<void>.delayed(Duration.zero);
    calls.add('first.boot');
  }

  @override
  void shutdown() => calls.add('first.shutdown');
}

class SecondProvider extends ServiceProvider {
  SecondProvider(super.app);
  @override
  void register() => calls.add('second.register');
  @override
  void boot() => calls.add('second.boot');
  @override
  void shutdown() => calls.add('second.shutdown');
}

void main() {
  late Directory dir;
  setUp(() {
    calls.clear();
    dir = Directory.systemTemp.createTempSync('app_test');
    File(
      p.join(dir.path, '.env'),
    ).writeAsStringSync('APP_NAME=FromEnv\nAPP_ENV=testing\nAPP_DEBUG=true');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Application> build() =>
      Application.configure(basePath: dir.path, environment: {})
          .withConfig({
            'app': {
              'name': env('APP_NAME', 'x'),
              'debug': envBool('APP_DEBUG'),
              'log_path': 'storage/logs/app.log',
            },
          })
          .withProviders([FirstProvider.new, SecondProvider.new])
          .create();

  test('loads .env before config is evaluated', () async {
    final application = await build();
    expect(application.config.get('app.name'), 'FromEnv');
    expect(application.environment, 'testing');
    expect(application.debug, isTrue);
  });

  test(
    'registers all providers before booting any, awaiting async boots',
    () async {
      await build();
      expect(calls, [
        'first.register',
        'second.register',
        'first.boot',
        'second.boot',
      ]);
    },
  );

  test(
    'sets Application.current, Config.current and the app() helper',
    () async {
      final application = await build();
      expect(identical(Application.current, application), isTrue);
      expect(config('app.name'), 'FromEnv');
      expect(app<Greeter>().name, 'FromEnv');
      expect(identical(app<Application>(), application), isTrue);
    },
  );

  test('path resolves relative to basePath and Log is configured', () async {
    final application = await build();
    expect(application.path('storage/logs'), p.join(dir.path, 'storage/logs'));
    expect(Log.filePath, p.join(dir.path, 'storage/logs/app.log'));
    expect(Log.environment, 'testing');
  });

  test('instance throws before any app is created', () {
    Application.reset();
    expect(() => Application.current, throwsStateError);
  });

  test('shutdown closes listeners then providers in reverse order', () async {
    final application = await build();
    final server = await application.serve(host: '127.0.0.1', port: 0);
    final port = server.port;

    await application.shutdown();

    expect(calls, [
      'first.register',
      'second.register',
      'first.boot',
      'second.boot',
      'second.shutdown',
      'first.shutdown',
    ]);
    await expectLater(
      HttpClient().getUrl(Uri.parse('http://127.0.0.1:$port')),
      throwsA(isA<SocketException>()),
    );
  });
}
