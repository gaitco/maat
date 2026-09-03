import 'dart:convert';

import 'package:crypto/crypto.dart';

class PusherSigner {
  PusherSigner(this._secret, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String _secret;
  final DateTime Function() _clock;

  Map<String, String> signHttp({
    required String method,
    required String path,
    required String body,
    required String key,
    required int timestamp,
  }) {
    final query = <String, String>{
      'auth_key': key,
      'auth_timestamp': '$timestamp',
      'auth_version': '1.0',
    };
    if (body.isNotEmpty) {
      query['body_md5'] = md5.convert(utf8.encode(body)).toString();
    }
    query['auth_signature'] = _signature(
      '$method\n$path\n${_canonicalQuery(query)}',
    );
    return query;
  }

  String subscriptionSignature(
    String socketId,
    String channelName, {
    String? channelData,
  }) => _signature(
    '$socketId:$channelName${channelData == null ? '' : ':$channelData'}',
  );

  bool secureEquals(String left, String right) {
    final leftBytes = _decodeHex(left);
    final rightBytes = _decodeHex(right);
    if (leftBytes == null ||
        rightBytes == null ||
        leftBytes.length != rightBytes.length) {
      return false;
    }

    var difference = 0;
    for (var index = 0; index < leftBytes.length; index++) {
      difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
  }

  bool verifyHttpRequest({
    required String method,
    required String path,
    required String body,
    required String key,
    required Map<String, String> query,
  }) {
    if (query['auth_key'] != key || query['auth_version'] != '1.0') {
      return false;
    }

    final timestamp = int.tryParse(query['auth_timestamp'] ?? '');
    final now =
        _clock().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    if (timestamp == null || (now - timestamp).abs() > 600) return false;

    final receivedMd5 = query['body_md5'];
    final signature = query['auth_signature'];
    if ((body.isNotEmpty && receivedMd5 == null) ||
        (receivedMd5 != null &&
            !secureEquals(
              md5.convert(utf8.encode(body)).toString(),
              receivedMd5,
            )) ||
        signature == null) {
      return false;
    }

    final canonical = Map<String, String>.of(query)..remove('auth_signature');
    return secureEquals(
      _signature('$method\n$path\n${_canonicalQuery(canonical)}'),
      signature,
    );
  }

  String _signature(String value) =>
      Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode(value)).toString();

  static String _canonicalQuery(Map<String, String> query) {
    final keys = query.keys.toList()..sort();
    return keys.map((key) => '$key=${query[key]!}').join('&');
  }

  static List<int>? _decodeHex(String value) {
    if (value.length.isOdd) return null;
    try {
      return [
        for (var index = 0; index < value.length; index += 2)
          int.parse(value.substring(index, index + 2), radix: 16),
      ];
    } on FormatException {
      return null;
    }
  }
}
