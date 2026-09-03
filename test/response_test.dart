import 'dart:convert';

import 'package:maat/maat.dart';
import 'package:test/test.dart';

class Money {
  Map<String, dynamic> toJson() => {'amount': 5};
}

void main() {
  test('json encodes body, sets content-type and status', () {
    final r = Response.json({'a': 1}, status: 201);
    expect(r.statusCode, 201);
    expect(r.headers['content-type'], 'application/json; charset=utf-8');
    expect(r.body, '{"a":1}');
  });

  test('json encodes DateTime as ISO-8601 and objects via toJson', () {
    final r = Response.json({'at': DateTime.utc(2026, 9, 2), 'm': Money()});
    expect(jsonDecode(r.body as String), {
      'at': '2026-09-02T00:00:00.000Z',
      'm': {'amount': 5},
    });
  });

  test('text, html, redirect, noContent', () {
    expect(
      Response.text('hi').headers['content-type'],
      'text/plain; charset=utf-8',
    );
    expect(
      Response.html('<b>').headers['content-type'],
      'text/html; charset=utf-8',
    );
    final redirect = Response.redirect('/login');
    expect(redirect.statusCode, 302);
    expect(redirect.headers['location'], '/login');
    expect(Response.noContent().statusCode, 204);
  });

  test('fluent status and headers return copies', () {
    final base = Response.text('x');
    final changed = base.status(418).header('X-A', '1').withHeaders({
      'X-B': '2',
    });
    expect(base.statusCode, 200);
    expect(changed.statusCode, 418);
    expect(changed.headers['x-a'], '1');
    expect(changed.headers['x-b'], '2');
  });

  group('from normalizes handler return values', () {
    test('Response passes through', () {
      final r = Response.text('x');
      expect(identical(Response.from(r), r), isTrue);
    });
    test('null -> 204', () => expect(Response.from(null).statusCode, 204));
    test(
      'String -> html',
      () => expect(
        Response.from('hi').headers['content-type'],
        contains('text/html'),
      ),
    );
    test('Map/List -> json', () {
      expect(Response.from({'a': 1}).body, '{"a":1}');
      expect(Response.from([1, 2]).body, '[1,2]');
    });
    test(
      'object with toJson -> json',
      () => expect(Response.from(Money()).body, '{"amount":5}'),
    );
    test(
      'other -> text of toString',
      () => expect(Response.from(42).body, '42'),
    );
  });

  test('toShelf carries status, body and headers', () async {
    final s = Response.json({
      'ok': true,
    }, status: 202).header('x-id', '9').toShelf();
    expect(s.statusCode, 202);
    expect(s.headers['x-id'], '9');
    expect(await s.readAsString(), '{"ok":true}');
  });

  test('stream passes chunks to Shelf without buffering them', () async {
    var emitted = false;
    final body = Stream<List<int>>.multi((controller) {
      emitted = true;
      controller
        ..add(utf8.encode('one'))
        ..add(utf8.encode('two'))
        ..close();
    });

    final response = Response.stream(body).toShelf();

    expect(emitted, isFalse);
    expect(await response.readAsString(), 'onetwo');
    expect(emitted, isTrue);
  });
}
