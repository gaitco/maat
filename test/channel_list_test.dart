import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Application app;
  late StringBuffer out;
  late Sesh maat;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('channel-list');
    app = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    app.instance<ChannelAuthorizationRegistry>(ChannelAuthorizationRegistry());
    out = StringBuffer();
    maat = Sesh(app, out: out, err: StringBuffer());
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('channel:list prints registered patterns in insertion order', () async {
    final registry = app.make<ChannelAuthorizationRegistry>();
    registry
      ..channel('orders.{id}', (user, params) => true)
      ..channel('chat.{roomId}', (user, params) => true)
      ..channel('orders.{id}', (user, params) => true);

    expect(await maat.run(['channel:list']), 0);
    final output = out.toString();
    expect(RegExp('orders\\.\\{id\\}').allMatches(output), hasLength(1));
    expect(RegExp('chat\\.\\{roomId\\}').allMatches(output), hasLength(1));
    expect(
      output.indexOf('orders.{id}'),
      lessThan(output.indexOf('chat.{roomId}')),
    );
  });
}
