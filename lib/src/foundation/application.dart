import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../auth/auth.dart';
import '../config/config.dart';
import '../config/env.dart';
import '../container/container.dart';
import '../events/dispatcher.dart';
import '../http/exception_handler.dart';
import '../http/kernel.dart';
import '../http/middleware/middleware.dart';
import '../routing/router.dart';
import '../support/log.dart';
import 'service_provider.dart';

/// The application: a [Container] plus lifecycle and the loaded config.
///
/// One application per process. Global helpers ([app], [config], [env],
/// [route] — see their respective files) and [Log]'s static state all
/// resolve against [Application.current], the most recently created
/// application (spec §5.2). Creating a second [Application] in the same
/// process redirects every one of those helpers to it, even for requests
/// still being served by the first application's [HttpKernel] — e.g. `Cors`
/// reading `config('cors')` mid-request would pick up the second app's
/// config. This is the intended contract, not a bug: tests and any other
/// code that builds multiple applications in one process must not
/// interleave requests between them.
class Application extends Container {
  Application._(this.basePath, this.env, this.config);

  static const version = '0.1.0';

  static Application? _instance;

  /// The most recently created application — see the class doc comment for
  /// the one-application-per-process contract this implies.
  static Application get current =>
      _instance ??
      (throw StateError(
        'No Application has been created yet. Call createApp() first.',
      ));

  /// Forget the current instance (tests only).
  ///
  /// Also clears [Auth]'s guard registry: it is static, so it would
  /// otherwise survive into the next [Application] this process builds —
  /// the same leak [Auth.reset] itself exists to prevent between tests.
  static void reset() {
    _instance = null;
    Auth.reset();
  }

  final String basePath;
  final Env env;
  final Config config;
  final List<ServiceProvider> _providers = [];
  final Set<HttpServer> _servers = {};
  Future<void>? _shutdown;

  List<ServiceProvider> get providers => List.unmodifiable(_providers);
  String get environment => env.get('APP_ENV') ?? 'production';
  bool get debug => config.get('app.debug') == true;

  /// Absolute path for a path relative to [basePath].
  String path(String relative) => p.join(basePath, relative);

  /// Serve HTTP. Direct servers bind exclusively unless a worker coordinator
  /// explicitly enables port sharing.
  Future<HttpServer> serve({
    String host = '0.0.0.0',
    int port = 8000,
    bool shared = false,
  }) async {
    final server = await shelf_io.serve(
      make<HttpKernel>().handleShelf,
      host,
      port,
      shared: shared,
    );
    _servers.add(server);
    Log.info('Maat listening on http://${server.address.host}:${server.port}');
    return server;
  }

  /// Stop accepting requests, wait for active requests, then release providers.
  Future<void> shutdown({bool force = false}) =>
      _shutdown ??= _shutdownApplication(force);

  Future<void> _shutdownApplication(bool force) async {
    await Future.wait([
      for (final server in _servers) server.close(force: force),
    ]);
    _servers.clear();
    for (final provider in _providers.reversed) {
      await provider.shutdown();
    }
  }

  /// Keep the process alive until SIGINT/SIGTERM, then shut down gracefully.
  Future<void> waitForShutdownSignal() => _waitForSignal(shutdown);

  /// Boot [workers] isolated applications sharing one HTTP port.
  ///
  /// [bootstrap] must be a top-level or static function so Dart can send it to
  /// worker isolates.
  static Future<ApplicationWorkers> serveWorkers(
    Future<Application> Function() bootstrap, {
    String host = '0.0.0.0',
    int port = 8000,
    int workers = 1,
  }) async {
    if (workers < 1) {
      throw ArgumentError.value(workers, 'workers', 'must be >= 1');
    }
    final running = <_ApplicationWorker>[];
    var sharedPort = port;
    try {
      if (workers > 1) {
        // ponytail: a process can claim the port after this probe closes;
        // distribute a parent-owned socket if that startup race is observed.
        final probe = await ServerSocket.bind(host, port);
        sharedPort = probe.port;
        await probe.close();
      }
      for (var i = 0; i < workers; i++) {
        final ready = ReceivePort();
        final exit = ReceivePort();
        await Isolate.spawn(
          _serveWorker,
          _WorkerStart(
            bootstrap,
            host,
            sharedPort,
            workers > 1,
            ready.sendPort,
          ),
          onExit: exit.sendPort,
          debugName: 'maat-worker-${i + 1}',
        );
        final message = await ready.first as List<Object?>;
        ready.close();
        if (message.first != 'ready') {
          await exit.first;
          exit.close();
          throw StateError(message[1] as String);
        }
        sharedPort = message[2] as int;
        running.add(_ApplicationWorker(message[1] as SendPort, exit));
      }
      return ApplicationWorkers._(running, sharedPort);
    } catch (_) {
      await ApplicationWorkers._(running, sharedPort).close(force: true);
      rethrow;
    }
  }

  /// Start building an application. Loads `.env` immediately so that `env()` works
  /// inside config files evaluated by `withConfig`.
  static ApplicationBuilder configure({
    required String basePath,
    Map<String, String>? environment,
  }) {
    Env.load(p.join(basePath, '.env'), environment: environment);
    return ApplicationBuilder._(basePath, Env.current);
  }
}

class ApplicationWorkers {
  ApplicationWorkers._(this._workers, this.port);

  final List<_ApplicationWorker> _workers;
  final int port;
  Future<void>? _closing;

  int get workerCount => _workers.length;

  Future<void> close({bool force = false}) => _closing ??= _closeWorkers(force);

  Future<void> _closeWorkers(bool force) async {
    for (final worker in _workers) {
      worker.control.send(force);
    }
    await Future.wait([for (final worker in _workers) worker.done]);
  }

  Future<void> waitForShutdownSignal() => _waitForSignal(close);
}

class _WorkerStart {
  _WorkerStart(this.bootstrap, this.host, this.port, this.shared, this.ready);
  final Future<Application> Function() bootstrap;
  final String host;
  final int port;
  final bool shared;
  final SendPort ready;
}

class _ApplicationWorker {
  _ApplicationWorker(this.control, ReceivePort exit)
    : done = exit.first.then((_) => exit.close());

  final SendPort control;
  final Future<void> done;
}

Future<void> _serveWorker(_WorkerStart start) async {
  final commands = ReceivePort();
  try {
    final application = await start.bootstrap();
    final server = await application.serve(
      host: start.host,
      port: start.port,
      shared: start.shared,
    );
    start.ready.send(['ready', commands.sendPort, server.port]);
    final force = await commands.first as bool;
    await application.shutdown(force: force);
  } catch (error, stackTrace) {
    start.ready.send(['error', '$error\n$stackTrace']);
  } finally {
    commands.close();
  }
}

Future<void> _waitForSignal(Future<void> Function({bool force}) close) async {
  final signal = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final processSignal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    subscriptions.add(
      processSignal.watch().listen((_) {
        if (!signal.isCompleted) signal.complete();
      }),
    );
  }
  await signal.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  await close(force: false);
}

class ApplicationBuilder {
  ApplicationBuilder._(this._basePath, this._env);

  final String _basePath;
  final Env _env;
  Map<String, dynamic> _config = {};
  final List<ServiceProvider Function(Application)> _providerFactories = [];
  final List<void Function(Application)> _configurators = [];

  ApplicationBuilder withConfig(Map<String, dynamic> config) {
    _config = config;
    return this;
  }

  ApplicationBuilder withProviders(
    List<ServiceProvider Function(Application app)> providers,
  ) {
    _providerFactories.addAll(providers);
    return this;
  }

  /// Internal hook used by `withMiddleware` / `withExceptions` (later tasks) to
  /// run configuration after core bindings exist but before providers register.
  ApplicationBuilder configureApp(void Function(Application app) configure) {
    _configurators.add(configure);
    return this;
  }

  /// Configure the global middleware stack and aliases, e.g. `bootstrap/app.dart`.
  ApplicationBuilder withMiddleware(
    void Function(MiddlewareConfig middleware) configure,
  ) => configureApp((app) => configure(app.make<MiddlewareConfig>()));

  /// Configure the exception handler, e.g. `bootstrap/app.dart`.
  ApplicationBuilder withExceptions(
    void Function(ExceptionHandler exceptions) configure,
  ) => configureApp((app) => configure(app.make<ExceptionHandler>()));

  Future<Application> create() async {
    final config = Config(_config);
    final app = Application._(_basePath, _env, config);
    Application._instance = app;
    Config.current = config;
    app.instance<Application>(app);
    app.instance<Config>(config);
    app.instance<Env>(_env);
    app.singleton<Router>((_) => Router());
    app.singleton<Dispatcher>((_) => Dispatcher());
    app.singleton<MiddlewareConfig>((_) => MiddlewareConfig());
    app.singleton<ExceptionHandler>(
      (_) => ExceptionHandler(debug: () => app.debug),
    );
    app.singleton<HttpKernel>((_) => HttpKernel(app));

    Log.environment = app.environment;
    final logPath = config.get('app.log_path');
    Log.filePath = logPath is String ? app.path(logPath) : null;

    for (final configure in _configurators) {
      configure(app);
    }

    for (final factory in _providerFactories) {
      app._providers.add(factory(app));
    }
    for (final provider in app._providers) {
      provider.register();
    }
    for (final provider in app._providers) {
      await provider.boot();
    }
    return app;
  }
}

/// Resolve [T] from the current application.
T app<T extends Object>() => Application.current.make<T>();
