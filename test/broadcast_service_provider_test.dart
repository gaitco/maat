import 'dart:io';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

class _BroadcastEvent implements ShouldBroadcast, BroadcastsWith {
  @override
  List<Channel> broadcastOn() => const [Channel('orders')];

  @override
  Map<String, Object?> broadcastWith() => const {'id': 7};
}

class _SuppressedBroadcastEvent implements ShouldBroadcast {
  @override
  List<Channel> broadcastOn() => const [Channel('suppressed')];
}

void main() {
  late Directory directory;

  setUp(() {
    Application.reset();
    directory = Directory.systemTemp.createTempSync('broadcast_provider');
  });

  tearDown(() {
    Application.reset();
    directory.deleteSync(recursive: true);
  });

  Future<Application> build(Map<String, dynamic> broadcasting) =>
      Application.configure(basePath: directory.path, environment: {})
          .withConfig({'broadcasting': broadcasting})
          .withProviders([BroadcastServiceProvider.new])
          .create();

  Map<String, dynamic> documentedLogConfig() => {
    'default': 'log',
    'connections': {
      'pusher': {
        'driver': 'pusher',
        'key': '',
        'secret': '',
        'app_id': '',
        'host': '127.0.0.1',
        'port': 6001,
        'scheme': 'http',
      },
      'log': {'driver': 'log'},
      'null': {'driver': 'null'},
    },
  };

  test(
    'binds one manager and authorization registry with built-in drivers',
    () async {
      final application = await build({
        'default': 'log',
        'connections': {
          'log': {'driver': 'log'},
          'null': {'driver': 'null'},
          'pusher': {
            'driver': 'pusher',
            'app_id': 'app-id',
            'key': 'app-key',
            'secret': 'app-secret',
            'host': 'localhost',
            'port': 6001,
            'scheme': 'http',
          },
        },
      });

      final manager = application.make<BroadcastManager>();
      expect(identical(manager, application.make<BroadcastManager>()), isTrue);
      expect(manager.connection('log'), isA<LogBroadcaster>());
      expect(manager.connection('null'), isA<NullBroadcaster>());
      expect(manager.connection('pusher'), isA<PusherBroadcaster>());
      expect(
        identical(
          application.make<ChannelAuthorizationRegistry>(),
          application.make<ChannelAuthorizationRegistry>(),
        ),
        isTrue,
      );
    },
  );

  test(
    'dispatches broadcast events through the currently bound manager',
    () async {
      final application = await build({
        'default': 'null',
        'connections': {
          'null': {'driver': 'null'},
        },
      });
      final fake = BroadcastFake();
      application.instance<BroadcastManager>(
        BroadcastManager({'fake': fake}, defaultConnection: 'fake'),
      );

      await application.make<Dispatcher>().dispatch(_BroadcastEvent());

      expect(fake.sent, hasLength(1));
      expect(fake.sent.single.channels, ['orders']);
      expect(fake.sent.single.payload, {'id': 7});
    },
  );

  test('keeps inactive documented Pusher credentials lazy', () async {
    final application = await build(documentedLogConfig());
    final manager = application.make<BroadcastManager>();

    expect(manager.connection(), isA<LogBroadcaster>());
    expect(identical(manager.connection(), manager.connection('log')), isTrue);
    expect(
      () => manager.connection('pusher'),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('broadcasting.connections.pusher.app_id'),
        ),
      ),
    );
  });

  test('installs the broadcast hook when Event.fake runs first', () async {
    final application =
        await Application.configure(basePath: directory.path, environment: {})
            .withConfig({
              'broadcasting': {
                'default': 'null',
                'connections': {
                  'null': {'driver': 'null'},
                },
              },
            })
            .configureApp((_) => Event.fake(only: [_SuppressedBroadcastEvent]))
            .withProviders([BroadcastServiceProvider.new])
            .create();
    final broadcasts = Broadcast.fake();

    await application.make<Dispatcher>().dispatch(_BroadcastEvent());

    broadcasts.assertBroadcasted('_BroadcastEvent');
  });

  test('event and broadcast fakes compose across public APIs', () async {
    await build({
      'default': 'null',
      'connections': {
        'null': {'driver': 'null'},
      },
    });
    final broadcasts = Broadcast.fake();
    final events = Event.fake(only: [_SuppressedBroadcastEvent]);

    await Event.dispatch(_SuppressedBroadcastEvent());
    await Event.dispatch(_BroadcastEvent());

    events.assertDispatched<_SuppressedBroadcastEvent>();
    events.assertNotDispatched<_BroadcastEvent>();
    broadcasts.assertNotBroadcasted('_SuppressedBroadcastEvent');
    broadcasts.assertBroadcasted('_BroadcastEvent');
  });

  test(
    'rejects missing and unknown driver configuration without values',
    () async {
      final missingDefault = await build({
        'connections': {
          'null': {'driver': 'null'},
        },
      });
      expect(
        missingDefault.make<BroadcastManager>,
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('broadcasting.default'),
          ),
        ),
      );

      final unknown = await build({
        'default': 'primary',
        'connections': {
          'primary': {'driver': 'very-sensitive-driver'},
        },
      });
      expect(
        unknown.make<BroadcastManager>,
        throwsA(
          isA<StateError>()
              .having(
                (error) => '$error',
                'message',
                contains('broadcasting.connections.primary.driver'),
              )
              .having(
                (error) => '$error',
                'message',
                isNot(contains('very-sensitive-driver')),
              ),
        ),
      );
    },
  );

  test(
    'names every missing Pusher credential without exposing secrets',
    () async {
      for (final key in ['app_id', 'key', 'secret']) {
        final connection = <String, Object?>{
          'driver': 'pusher',
          'app_id': 'app-id',
          'key': 'app-key',
          'secret': 'app-secret',
        }..remove(key);
        final application = await build({
          'default': 'pusher',
          'connections': {'pusher': connection},
        });

        expect(
          () => application.make<BroadcastManager>().connection('pusher'),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => '$error',
                  'message',
                  contains('broadcasting.connections.pusher.$key'),
                )
                .having(
                  (error) => '$error',
                  'message',
                  isNot(anyOf(contains('app-id'), contains('app-secret'))),
                ),
          ),
        );
      }
    },
  );
}
