import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  Future<void> boot({bool debug = true, String? assetUrl}) async {
    await Application.configure(basePath: dir.path, environment: {}).withConfig(
      {
        'app': {'name': 'Test', 'debug': debug, 'asset_url': ?assetUrl},
      },
    ).create();
  }

  void write(String relative, String contents) => File('${dir.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() => dir = Directory.systemTemp.createTempSync('maat_paths'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('debug mode returns the bare path', () async {
    write('public/build/app.css', '.a{}');
    await boot();
    expect(asset('build/app.css'), '/build/app.css');
  });

  test('outside debug mode a cache-busting token is appended', () async {
    write('public/build/app.css', '.a{}');
    await boot(debug: false);
    expect(
      asset('build/app.css'),
      matches(r'^/build/app\.css\?v=[0-9a-f]{8}$'),
    );
  });

  test('different contents produce a different token', () async {
    write('public/build/app.css', '.a{}');
    await boot(debug: false);
    final first = asset('build/app.css');
    write('public/build/app.css', '.b{color:red;padding:1px}');
    await boot(debug: false);
    expect(asset('build/app.css'), isNot(first));
  });

  test(
    'a missing file resolves to the bare path rather than throwing',
    () async {
      await boot(debug: false);
      expect(asset('build/app.css'), '/build/app.css');
    },
  );

  test('asset_url still prefixes the URL, with the token kept', () async {
    write('public/build/app.css', '.a{}');
    await boot(debug: false, assetUrl: 'https://cdn.example.com');
    expect(
      asset('build/app.css'),
      startsWith('https://cdn.example.com/build/app.css?v='),
    );
  });

  test('asset_url in debug mode has no token', () async {
    write('public/build/app.css', '.a{}');
    await boot(assetUrl: 'https://cdn.example.com/');
    expect(asset('build/app.css'), 'https://cdn.example.com/build/app.css');
  });
}
