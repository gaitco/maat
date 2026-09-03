import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

Future<Application> bootstrapWorkerApp() async {
  final application = await Application.configure(
    basePath: Directory.systemTemp.path,
    environment: const {},
  ).create();
  Route.get(
    '/worker',
    (Request request) => {'isolate': Isolate.current.hashCode},
  );
  return application;
}

void main() {
  test('serve refuses a port already shared by another server', () async {
    final occupied = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    addTearDown(() => occupied.close(force: true));
    final application = await bootstrapWorkerApp();
    addTearDown(() => application.shutdown(force: true));

    await expectLater(
      application.serve(host: '127.0.0.1', port: occupied.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('serveWorkers refuses a port shared by another server', () async {
    final occupied = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    addTearDown(() => occupied.close(force: true));

    try {
      final server = await Application.serveWorkers(
        bootstrapWorkerApp,
        host: '127.0.0.1',
        port: occupied.port,
        workers: 2,
      );
      await server.close(force: true);
      fail('serveWorkers bound a port owned by another server');
    } on SocketException {
      // Expected: an unrelated listener owns the requested port.
    }
  });

  test(
    'serveWorkers boots workers on one port and closes them together',
    () async {
      final server = await Application.serveWorkers(
        bootstrapWorkerApp,
        host: '127.0.0.1',
        port: 0,
        workers: 2,
      );
      addTearDown(() => server.close(force: true));

      expect(server.workerCount, 2);
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/worker'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
        jsonDecode(await response.transform(utf8.decoder).join())['isolate'],
        isA<int>(),
      );
      client.close();

      await server.close();
      await expectLater(
        HttpClient().getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/worker'),
        ),
        throwsA(isA<SocketException>()),
      );
    },
  );
}
