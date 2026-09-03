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
