import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Sesh maat;
  late Application app;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gen');
    app = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    out = StringBuffer();
    err = StringBuffer();
    maat = Sesh(app, out: out, err: err);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String rel) => File(p.join(dir.path, rel)).readAsStringSync();

  test('make:controller plain and --api', () async {
    expect(await maat.run(['make:controller', 'PostController']), 0);
    final plain = read('lib/app/http/controllers/post_controller.dart');
    expect(plain, contains("import 'package:maat/maat.dart';"));
    expect(plain, contains('class PostController extends Controller'));
    expect(
      out.toString(),
      contains(
        'Controller [lib/app/http/controllers/post_controller.dart] created successfully.',
      ),
    );

    expect(
      await maat.run(['make:controller', 'Admin/UserController', '--api']),
      0,
    );
    final api = read('lib/app/http/controllers/admin/user_controller.dart');
    expect(api, contains('class UserController extends ResourceController'));
    for (final m in [
      'index(Request request)',
      'store(Request request)',
      'show(Request request, String id)',
      'update(Request request, String id)',
      'destroy(Request request, String id)',
    ]) {
      expect(api, contains(m));
    }
    expect(await maat.run(['make:controller', 'X', '--resource']), 0);
    expect(
      read('lib/app/http/controllers/x.dart'),
      contains('ResourceController'),
    );
  });

  test('make:controller --invokable', () async {
    expect(
      await maat.run(['make:controller', 'ShowProfile', '--invokable']),
      0,
    );
    final src = read('lib/app/http/controllers/show_profile.dart');
    expect(src, contains('class ShowProfile extends Controller'));
    expect(src, contains('FutureOr<Object?> call(Request request)'));
  });

  test('refuses to overwrite unless --force', () async {
    await maat.run(['make:controller', 'PostController']);
    expect(await maat.run(['make:controller', 'PostController']), 1);
    expect(err.toString(), contains('already exists'));
    expect(await maat.run(['make:controller', 'PostController', '--force']), 0);
  });

  test('make:middleware', () async {
    await maat.run(['make:middleware', 'EnsureAdmin']);
    final code = read('lib/app/http/middleware/ensure_admin.dart');
    expect(code, contains('class EnsureAdmin extends Middleware'));
    expect(
      code,
      contains('FutureOr<Response> handle(Request request, Next next)'),
    );
    expect(code, contains('return next(request);'));
  });

  test('make:request', () async {
    await maat.run(['make:request', 'StorePostRequest']);
    final code = read('lib/app/http/requests/store_post_request.dart');
    expect(code, contains('class StorePostRequest extends FormRequest'));
    expect(code, contains('Map<String, Object> rules()'));
    expect(code, contains('bool authorize(Request request)'));
  });

  test('make:provider', () async {
    await maat.run(['make:provider', 'BillingServiceProvider']);
    final code = read('lib/app/providers/billing_service_provider.dart');
    expect(
      code,
      contains('class BillingServiceProvider extends ServiceProvider'),
    );
    expect(code, contains('BillingServiceProvider(super.app);'));
    expect(code, contains('void register()'));
    expect(code, contains('boot()'));
  });

  test('make:command', () async {
    await maat.run(['make:command', 'SendEmails']);
    final code = read('lib/app/console/commands/send_emails.dart');
    expect(code, contains('class SendEmails extends Command'));
    expect(code, contains("String get name => 'app:send-emails';"));
    expect(code, contains('Future<int> handle()'));
  });

  test(
    'generated files compile inside a package that depends on maat',
    () async {
      final frameworkPath = p.normalize(p.join(Directory.current.path));
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: genapp
environment:
  sdk: ^3.12.0
dependencies:
  maat:
    path: $frameworkPath
''');
      await maat.run(['make:controller', 'PostController', '--api']);
      await maat.run(['make:controller', 'PageController']);
      await maat.run(['make:middleware', 'EnsureAdmin']);
      await maat.run(['make:request', 'StorePostRequest']);
      await maat.run(['make:provider', 'BillingServiceProvider']);
      await maat.run(['make:command', 'SendEmails']);
      await maat.run(['make:event', 'OrderShipped']);
      await maat.run([
        'make:listener',
        'SendShipmentNotification',
        '--event=OrderShipped',
      ]);
      final pubGet = await Process.run('dart', [
        'pub',
        'get',
      ], workingDirectory: dir.path);
      expect(pubGet.exitCode, 0, reason: pubGet.stderr.toString());
      final analyze = await Process.run('dart', [
        'analyze',
        '--fatal-infos',
      ], workingDirectory: dir.path);
      expect(analyze.exitCode, 0, reason: '${analyze.stdout}${analyze.stderr}');

      // Generated code lands in the user's repository already formatted:
      // the stubs are written as plain Dart and the generator runs
      // `dart format` over what it wrote, so no name length can leave a file
      // one `dart format .` away from tidy.
      final format = await Process.run('dart', [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        '.',
      ], workingDirectory: dir.path);
      expect(format.exitCode, 0, reason: '${format.stdout}${format.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a file whose formatting fails is kept and still reported', () async {
    final maat = Sesh(
      app,
      out: out,
      err: err,
      commands: [_UnparsableCommand()],
    );

    expect(await maat.run(['make:broken', 'Widget']), 0);

    // The file on disk is what the stub produced. Unformatted output is a
    // cosmetic loss; deleting the generated file would not be.
    expect(read('lib/app/broken/widget.dart'), 'class Widget {');
    expect(out.toString(), contains('WARNING'));
    expect(out.toString(), contains('could not be parsed'));
    expect(
      out.toString(),
      contains('Broken [lib/app/broken/widget.dart] created successfully.'),
    );
  });
}

/// Emits Dart that `dart format` cannot parse, so the formatting step fails
/// for a reason no stub of the framework's own can produce on purpose.
class _UnparsableCommand extends GeneratorCommand {
  @override
  String get name => 'make:broken';

  @override
  String get description => 'Writes a stub the formatter cannot parse';

  @override
  String get type => 'Broken';

  @override
  String get directory => 'lib/app/broken';

  @override
  String stub(String className) => 'class $className {';
}
