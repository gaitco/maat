import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Sesh maat;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('make-channel');
    final app = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    maat = Sesh(app, out: StringBuffer(), err: StringBuffer());
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('make:channel generates a deny-by-default authorizer', () async {
    expect(await maat.run(['make:channel', 'OrdersChannel']), 0);

    final file = File(p.join(dir.path, 'routes', 'orders_channel.dart'));
    expect(file.readAsStringSync(), '''import 'package:maat/maat.dart';

void registerOrdersChannel() {
  Broadcast.channel('orders.{id}', (user, params) async {
    // TODO: Replace with application-specific ownership logic.
    return false;
  });
}
''');
  });
}
