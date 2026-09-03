import 'dart:io';

import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

class _User {
  _User(this.id, this.name, this.email);
  final int id;
  final String name;
  final String email;
}

class _UserResource extends JsonResource<_User> {
  _UserResource(super.resource, {this.admin = false});
  final bool admin;

  @override
  Map<String, Object?> toJson(Request request) => {
    'id': resource.id,
    'name': resource.name,
    'email': when(admin, () => resource.email),
  };
}

void main() {
  final req = Request.create(method: 'GET', path: '/');

  test('when(true) includes the key', () {
    final out = _UserResource(
      _User(1, 'Ada', 'a@x.y'),
      admin: true,
    ).resolve(req);
    expect(out['data'], {'id': 1, 'name': 'Ada', 'email': 'a@x.y'});
  });

  test('when(false) REMOVES the key rather than nulling it', () {
    final out = _UserResource(_User(1, 'Ada', 'a@x.y')).resolve(req);
    expect((out['data']! as Map).containsKey('email'), isFalse);
    expect(out['data'], {'id': 1, 'name': 'Ada'});
  });

  test('the when callback is lazy', () {
    var ran = false;
    final r = _LazyResource(_User(1, 'Ada', 'a@x.y'), () {
      ran = true;
      return 1;
    });
    r.resolve(req);
    expect(
      ran,
      isFalse,
      reason: 'callback must not run when the condition is false',
    );
  });

  test('wrapping can be disabled', () {
    final out = _UnwrappedResource(_User(1, 'Ada', 'a@x.y')).resolve(req);
    expect(out.containsKey('data'), isFalse);
    expect(out['id'], 1);
  });

  test('additional() merges top-level keys alongside data', () {
    final out = _UserResource(_User(1, 'Ada', 'a@x.y'))
        .additional({
          'meta': {'version': 2},
        })
        .resolve(req);
    expect(out['meta'], {'version': 2});
    expect((out['data']! as Map)['id'], 1);
  });

  test('missing values are stripped from nested maps and lists', () {
    final out = _NestedResource(_User(1, 'Ada', 'a@x.y')).resolve(req);
    final data = out['data']! as Map<String, Object?>;
    expect((data['nested']! as Map).containsKey('hidden'), isFalse);
    expect(data['list'], [1, 3]);
  });

  test('whenLoaded returns the relation when the model has it loaded', () {
    final out = _RelationResource(
      _FakeModel({
        'posts': [1, 2],
      }),
    ).resolve(req);
    expect((out['data']! as Map)['posts'], [1, 2]);
  });

  test('whenLoaded removes the key when the relation is not loaded', () {
    final out = _RelationResource(_FakeModel(const {})).resolve(req);
    expect((out['data']! as Map).containsKey('posts'), isFalse);
  });

  test(
    'whenLoaded on a non-model resource removes the key instead of throwing',
    () {
      final out = _PlainRelationResource(_User(1, 'Ada', 'a@x.y')).resolve(req);
      expect((out['data']! as Map).containsKey('posts'), isFalse);
    },
  );

  test('additional() cannot clobber the resource payload', () {
    final out = _UserResource(
      _User(1, 'Ada', 'a@x.y'),
    ).additional({'data': 'hijacked'}).resolve(req);
    expect(out['data'], {'id': 1, 'name': 'Ada'});
  });

  test('additional() values are stripped like the body', () {
    final out = _UserResource(_User(1, 'Ada', 'a@x.y'))
        .additional({
          'author': _UserResource(_User(2, 'Bob', 'b@x.y')),
          // when(false, ...) is the only way to obtain the sentinel: it is private.
          'gone': _UserResource(_User(3, 'Eve', 'e@x.y')).when(false, () => 1),
        })
        .resolve(req);
    expect(out['author'], {'id': 2, 'name': 'Bob'});
    expect(out.containsKey('gone'), isFalse);
  });

  test('a route returning a resource renders as JSON end to end', () async {
    final dir = Directory.systemTemp.createTempSync('jr');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app = await Application.configure(
      basePath: dir.path,
      environment: {},
    ).create();
    Route.get('/me', (Request r) => _UserResource(_User(1, 'Ada', 'a@x.y')));
    final res = await TestClient(app).get('/me');
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('application/json'));
    expect(res.body, '{"data":{"id":1,"name":"Ada"}}');
  });

  test('a nested JsonResource is inlined, unwrapped, and stripped', () {
    final out = _ParentResource(_User(1, 'Ada', 'a@x.y')).resolve(req);
    final data = out['data']! as Map<String, Object?>;
    final child = data['child']! as Map<String, Object?>;
    expect(
      child.containsKey('data'),
      isFalse,
      reason: 'nested resources are not wrapped',
    );
    expect(child, {'id': 1, 'name': 'Ada'});
    expect(data['children'], [
      {'id': 1, 'name': 'Ada'},
    ]);
  });

  test('a const Object() in the payload SURVIVES the strip', () {
    // The sentinel must not be `const`: Dart canonicalises const objects
    // program-wide, so a `const Object()` sentinel would be the very same
    // instance as one a developer writes into their own payload, and their key
    // would vanish from the response with no error at all.
    final data =
        _ConstObjectResource(_User(1, 'Ada', 'a@x.y')).resolve(req)['data']!
            as Map<String, Object?>;
    expect(data.containsKey('marker'), isTrue);
    expect(data['marker'], same(const Object()));
  });

  test('isMissing recognises the marker and nothing else', () {
    final resource = _UserResource(_User(1, 'Ada', 'a@x.y'));
    expect(JsonResource.isMissing(resource.when(false, () => 'x')), isTrue);
    expect(JsonResource.isMissing(resource.when(true, () => 'x')), isFalse);
    expect(JsonResource.isMissing(resource.whenLoaded('posts')), isTrue);
    expect(JsonResource.isMissing(const Object()), isFalse);
    expect(JsonResource.isMissing(Object()), isFalse);
    expect(JsonResource.isMissing(null), isFalse);
  });
}

class _LazyResource extends JsonResource<_User> {
  _LazyResource(super.resource, this.build);
  final Object? Function() build;
  @override
  Map<String, Object?> toJson(Request request) => {'x': when(false, build)};
}

class _UnwrappedResource extends JsonResource<_User> {
  _UnwrappedResource(super.resource);
  @override
  bool get wrap => false;
  @override
  Map<String, Object?> toJson(Request request) => {'id': resource.id};
}

class _NestedResource extends JsonResource<_User> {
  _NestedResource(super.resource);
  @override
  Map<String, Object?> toJson(Request request) => {
    'nested': {'shown': 1, 'hidden': when(false, () => 2)},
    'list': [1, when(false, () => 2), 3],
  };
}

/// Stands in for a `maat_seshat_core` model: `packages/maat` must not depend
/// on the ORM, so `whenLoaded` reaches for `loadedRelations` dynamically.
class _FakeModel {
  _FakeModel(this.loadedRelations);
  final Map<String, Object?> loadedRelations;
}

class _RelationResource extends JsonResource<_FakeModel> {
  _RelationResource(super.resource);
  @override
  Map<String, Object?> toJson(Request request) => {
    'posts': whenLoaded('posts'),
  };
}

class _PlainRelationResource extends JsonResource<_User> {
  _PlainRelationResource(super.resource);
  @override
  Map<String, Object?> toJson(Request request) => {
    'posts': whenLoaded('posts'),
  };
}

class _ParentResource extends JsonResource<_User> {
  _ParentResource(super.resource);
  @override
  Map<String, Object?> toJson(Request request) => {
    'child': _UserResource(resource),
    'children': [_UserResource(resource)],
  };
}

class _ConstObjectResource extends JsonResource<_User> {
  _ConstObjectResource(super.resource);
  @override
  Map<String, Object?> toJson(Request request) => {'marker': const Object()};
}
