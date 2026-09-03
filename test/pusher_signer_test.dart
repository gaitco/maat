import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  test('signs the canonical Pusher HTTP request', () {
    const body =
        r'{"name":"TaskChanged","channels":["tasks"],"data":"{\"id\":1}"}';
    final signer = PusherSigner('app-secret');
    final signed = signer.signHttp(
      method: 'POST',
      path: '/apps/app-id/events',
      body: body,
      key: 'app-key',
      timestamp: 1725321600,
    );
    expect(signed['body_md5'], 'd55efcc7779c00c094b11b834e54e6b8');
    expect(
      signed['auth_signature'],
      '4b757a7c14e3789dc428e4c0fd77990b101e26e3fc4a4f4086b2f52f146e7629',
    );
  });

  test('signs a bodyless GET without a body hash', () {
    final signed = PusherSigner('app-secret').signHttp(
      method: 'GET',
      path: '/apps/app-id/channels',
      body: '',
      key: 'app-key',
      timestamp: 1725321600,
    );

    expect(signed, const {
      'auth_key': 'app-key',
      'auth_timestamp': '1725321600',
      'auth_version': '1.0',
      'auth_signature':
          'f72d06361807ae1eadb42fea932e17f5f6dcea29cc9f4f1cc3c4e35c12827f2c',
    });
  });

  test('signs private and presence subscriptions', () {
    final signer = PusherSigner('app-secret');
    expect(
      signer.subscriptionSignature('123.456', 'private-orders.1'),
      'd5ddd577b56ebc9ed89f55ec4e3aa51f5f2b5691714eda41028fb9e7ab2b7283',
    );
    const data = r'{"user_id":"7","user_info":{"name":"Ada"}}';
    expect(
      signer.subscriptionSignature(
        '123.456',
        'presence-chat.1',
        channelData: data,
      ),
      '79ba2d807d9926772539eef9cfe77affc503a832add932c5f53d2d7c4f3311be',
    );
  });

  test('verifies a current canonical HTTP signature', () {
    const body =
        r'{"name":"TaskChanged","channels":["tasks"],"data":"{\"id\":1}"}';
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );

    expect(
      signer.verifyHttpRequest(
        method: 'POST',
        path: '/apps/app-id/events',
        body: body,
        key: 'app-key',
        query: const {
          'auth_key': 'app-key',
          'auth_timestamp': '1725321600',
          'auth_version': '1.0',
          'body_md5': 'd55efcc7779c00c094b11b834e54e6b8',
          'auth_signature':
              '4b757a7c14e3789dc428e4c0fd77990b101e26e3fc4a4f4086b2f52f146e7629',
        },
      ),
      isTrue,
    );
  });

  test('verifies the fixed bodyless GET vector without a body hash', () {
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );

    expect(
      signer.verifyHttpRequest(
        method: 'GET',
        path: '/apps/app-id/channels',
        body: '',
        key: 'app-key',
        query: const {
          'auth_key': 'app-key',
          'auth_timestamp': '1725321600',
          'auth_version': '1.0',
          'auth_signature':
              'f72d06361807ae1eadb42fea932e17f5f6dcea29cc9f4f1cc3c4e35c12827f2c',
        },
      ),
      isTrue,
    );
  });

  test('validates a supplied hash on a bodyless request', () {
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );
    const valid = {
      'auth_key': 'app-key',
      'auth_timestamp': '1725321600',
      'auth_version': '1.0',
      'body_md5': 'd41d8cd98f00b204e9800998ecf8427e',
      'auth_signature':
          '177d9d9a999797fee2c738b183382561cc5dc77c327b8d2ff21eeb31565a9a57',
    };

    bool verify(Map<String, String> query) => signer.verifyHttpRequest(
      method: 'GET',
      path: '/apps/app-id/channels',
      body: '',
      key: 'app-key',
      query: query,
    );

    expect(verify(valid), isTrue);
    expect(
      verify({...valid, 'body_md5': '00000000000000000000000000000000'}),
      isFalse,
    );
  });

  test('joins every sorted raw query pair when verifying', () {
    const body =
        r'{"name":"TaskChanged","channels":["tasks"],"data":"{\"id\":1}"}';
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );

    expect(
      signer.verifyHttpRequest(
        method: 'POST',
        path: '/apps/app-id/events',
        body: body,
        key: 'app-key',
        query: const {
          'name space': 'a/b c',
          'body_md5': 'd55efcc7779c00c094b11b834e54e6b8',
          'auth_version': '1.0',
          'auth_key': 'app-key',
          'auth_signature':
              'eaa9049c59362e88e3fb69420d8cd429053145211744f08415a129c085728afe',
          'auth_timestamp': '1725321600',
        },
      ),
      isTrue,
    );
  });

  test('rejects invalid Pusher HTTP authentication fields', () {
    const body =
        r'{"name":"TaskChanged","channels":["tasks"],"data":"{\"id\":1}"}';
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );
    const valid = {
      'auth_key': 'app-key',
      'auth_timestamp': '1725321600',
      'auth_version': '1.0',
      'body_md5': 'd55efcc7779c00c094b11b834e54e6b8',
      'auth_signature':
          '4b757a7c14e3789dc428e4c0fd77990b101e26e3fc4a4f4086b2f52f146e7629',
    };

    bool verify(Map<String, String> query, {String requestBody = body}) =>
        signer.verifyHttpRequest(
          method: 'POST',
          path: '/apps/app-id/events',
          body: requestBody,
          key: 'app-key',
          query: query,
        );

    expect(verify({...valid, 'auth_key': 'other-key'}), isFalse);
    expect(verify({...valid, 'auth_version': '2.0'}), isFalse);
    expect(verify({...valid, 'auth_timestamp': '1725322201'}), isFalse);
    expect(verify({...valid, 'auth_timestamp': 'not-a-number'}), isFalse);
    expect(verify(valid, requestBody: '{}'), isFalse);
    expect(verify({...valid, 'auth_signature': '00'}), isFalse);
  });

  test('accepts exact timestamp limits and rejects one second beyond', () {
    final signer = PusherSigner(
      'app-secret',
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1725321600 * 1000, isUtc: true),
    );
    const cases = [
      (
        '1725321000',
        '5629228c00256b274064c6508171e7d5a8b7af278c1d96869f20236b805b399e',
        true,
      ),
      (
        '1725322200',
        '9fa36d55efefc33d65809058d851890486b9d71d19ab5af3f5295d4c6bb17c95',
        true,
      ),
      (
        '1725320999',
        'fd1b73fdde02d8575ad82095a992d8d339a67c16170ba3a70ebfa915f391263e',
        false,
      ),
      (
        '1725322201',
        '5311da0ec9604f50a5547ed98ba2d15c8398b7fcda64af6c2835ec4477461ac7',
        false,
      ),
    ];

    for (final (timestamp, signature, expected) in cases) {
      expect(
        signer.verifyHttpRequest(
          method: 'POST',
          path: '/apps/app-id/events',
          body: '{}',
          key: 'app-key',
          query: {
            'auth_key': 'app-key',
            'auth_timestamp': timestamp,
            'auth_version': '1.0',
            'body_md5': '99914b932bd37a50b983c5e7c90ae93b',
            'auth_signature': signature,
          },
        ),
        expected,
        reason: 'timestamp $timestamp',
      );
    }
  });

  test('securely compares decoded hexadecimal signatures', () {
    final signer = PusherSigner('app-secret');

    expect(signer.secureEquals('00ff', '00ff'), isTrue);
    expect(signer.secureEquals('00ff', '00fe'), isFalse);
    expect(signer.secureEquals('00ff', '00'), isFalse);
    expect(signer.secureEquals('not-hex', 'not-hex'), isFalse);
    expect(signer.secureEquals('zz', 'zz'), isFalse);
  });
}
