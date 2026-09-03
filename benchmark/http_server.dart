import 'dart:io';

import 'package:maat/maat.dart';

Future<Application> createBenchmarkApp() async {
  final application = await Application.configure(
    basePath: Directory.current.path,
    environment: const {},
  ).create();
  final routes = int.tryParse(Platform.environment['BENCH_ROUTES'] ?? '') ?? 1;
  for (var i = 0; i < routes; i++) {
    Route.get('/route-$i', (Request request) => {'ok': true});
  }
  return application;
}

Future<void> main() async {
  final host = Platform.environment['APP_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['APP_PORT'] ?? '') ?? 8080;
  final workers = int.tryParse(Platform.environment['APP_WORKERS'] ?? '') ?? 1;
  final server = await Application.serveWorkers(
    createBenchmarkApp,
    host: host,
    port: port,
    workers: workers,
  );
  await server.waitForShutdownSignal();
}
