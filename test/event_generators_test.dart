import 'dart:io';

import 'package:maat/maat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Sesh sesh;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('event-generator');
    final application = await Application.configure(
      basePath: directory.path,
      environment: {},
    ).create();
    out = StringBuffer();
    err = StringBuffer();
    sesh = Sesh(application, out: out, err: err);
  });
  tearDown(() {
    Application.reset();
    directory.deleteSync(recursive: true);
  });

  String read(String relative) =>
      File(p.join(directory.path, relative)).readAsStringSync();

  test('make:event creates a Dispatchable event', () async {
    expect(await sesh.run(['make:event', 'OrderShipped']), 0);

    final source = read('lib/app/events/order_shipped.dart');
    expect(source, contains("import 'package:maat/maat.dart';"));
    expect(source, contains('class OrderShipped with Dispatchable'));
    expect(
      out.toString(),
      contains(
        'Event [lib/app/events/order_shipped.dart] created successfully.',
      ),
    );
  });

  test('make:listener types and imports its event', () async {
    expect(
      await sesh.run([
        'make:listener',
        'SendShipmentNotification',
        '--event=OrderShipped',
      ]),
      0,
    );

    final source = read('lib/app/listeners/send_shipment_notification.dart');
    expect(source, contains("import '../events/order_shipped.dart';"));
    expect(
      source,
      contains('class SendShipmentNotification extends Listener<OrderShipped>'),
    );
    expect(source, contains('Future<void> handle(OrderShipped event) async'));
  });

  test('make:listener without an event listens to Object', () async {
    expect(await sesh.run(['make:listener', 'LogEverything']), 0);

    final source = read('lib/app/listeners/log_everything.dart');
    expect(source, isNot(contains('../events/')));
    expect(source, contains('class LogEverything extends Listener<Object>'));
  });

  test('generated event is not overwritten without --force', () async {
    expect(await sesh.run(['make:event', 'OrderShipped']), 0);
    expect(await sesh.run(['make:event', 'OrderShipped']), 1);
    expect(err.toString(), contains('already exists'));
    expect(await sesh.run(['make:event', 'OrderShipped', '--force']), 0);
  });
}
