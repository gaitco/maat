import 'package:maat/src/api/api_document.dart';
import 'package:maat/src/api/schema.dart';
import 'package:maat/src/http/request.dart';
import 'package:maat/src/routing/router.dart';
import 'package:test/test.dart';

Object? handler(Request request) => null;
Object? handlerWithId(Request request, String id) => null;

const info = ApiInfo(title: 'Catalog', version: '1.0.0');

ApiDocument documentOf(Router router) =>
    ApiDocument.fromRouter(router, info: info);

const bookSchema = ApiSchema.object({
  'id': ApiSchema.integer(),
  'title': ApiSchema.string(),
}, name: 'Book');

void main() {
  late Router router;

  setUp(() => router = Router());

  test('only routes carrying a contract are documented', () {
    router.add(['GET'], '/pages', handler);
    router.add(['GET'], '/books', handler).responds(bookSchema);

    final document = documentOf(router);
    expect(document.operations, hasLength(1));
    expect(document.operations.single.path, '/books');
  });

  test('a contract on a route with no documentable verb fails loudly', () {
    router.add(['OPTIONS'], '/books', handler).summary('Preflight');

    expect(
      () => documentOf(router),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('OPTIONS /books'),
        ),
      ),
    );
  });

  test('HEAD and OPTIONS are not documented', () {
    router.add(['GET', 'HEAD', 'OPTIONS'], '/books', handler).summary('List');

    expect(documentOf(router).operations.map((o) => o.method), ['GET']);
  });

  group('parameters', () {
    test('path parameters come from the URI and default to string', () {
      router.add(['GET'], '/books/{id}', handlerWithId).summary('Show');

      final parameter = documentOf(router).operations.single.parameters.single;
      expect(parameter.name, 'id');
      expect(parameter.location, 'path');
      expect(parameter.schema.type, ApiType.string);
      expect(parameter.required, isTrue);
    });

    test('a path parameter can be typed with rules', () {
      router.add(['GET'], '/books/{id}', handlerWithId).params({
        'id': 'required|integer|min:1',
      });

      final parameter = documentOf(router).operations.single.parameters.single;
      expect(parameter.schema.type, ApiType.integer);
      expect(parameter.schema.minimum, 1);
      // Presence is carried by `required`, not repeated inside the schema.
      expect(parameter.schema.isOptional, isFalse);
    });

    test('typing an unknown parameter fails loudly', () {
      final route = router.add(['GET'], '/books/{id}', handlerWithId);
      expect(
        () => route.params({'slug': 'string'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('/books/{id}'), contains('slug')),
          ),
        ),
      );
    });

    test('query rules become query parameters with their own presence', () {
      router.add(['GET'], '/books', handler).query({
        'q': 'string|max:50',
        'page': 'required|integer|min:1',
      });

      final parameters = documentOf(router).operations.single.queryParameters;
      expect(parameters.map((p) => p.name), ['q', 'page']);
      expect(parameters.first.required, isFalse);
      expect(parameters.first.schema.maxLength, 50);
      expect(parameters.last.required, isTrue);
    });

    test('an optional path parameter loses its question mark', () {
      router.add(['GET'], '/books/{id?}', handlerWithId).summary('Show');

      expect(documentOf(router).operations.single.path, '/books/{id}');
    });
  });

  group('request bodies', () {
    test('body rules become a named request schema', () {
      router.add(['POST'], '/books', handler).name('books.store').body({
        'title': 'required|string|max:120',
      });

      final body = documentOf(router).operations.single.requestBody!;
      expect(body.name, 'BooksStoreRequest');
      expect(body.properties!['title']!.maxLength, 120);
    });

    test('a route without a body declares none', () {
      router.add(['GET'], '/books', handler).responds(bookSchema);

      expect(documentOf(router).operations.single.requestBody, isNull);
    });
  });

  group('responses', () {
    test('a contract without a declared success gets an unknown 200', () {
      router.add(['GET'], '/health', handler).summary('Health');

      final response = documentOf(router).operations.single.responses.single;
      expect(response.status, 200);
      expect(response.schema.type, ApiType.any);
    });

    test('declared responses are sorted by status', () {
      router
          .add(['POST'], '/books', handler)
          .responds(bookSchema, status: 201)
          .responds(const ApiSchema.none(), status: 204);

      expect(
        documentOf(router).operations.single.responses.map((r) => r.status),
        [201, 204],
      );
    });

    test('input implies a 422 with the shape Maat actually renders', () {
      router.add(['POST'], '/books', handler).body({'title': 'required'});

      final response = documentOf(
        router,
      ).operations.single.responses.singleWhere((r) => r.status == 422);
      expect(response.schema.name, 'ValidationError');
      expect(response.schema.properties!.keys, ['message', 'errors']);
    });

    test('a secured route implies a 401', () {
      router
          .add(['GET'], '/user', handler)
          .middleware(['auth:cartouche'])
          .responds(bookSchema);

      final statuses = documentOf(
        router,
      ).operations.single.responses.map((r) => r.status);
      expect(statuses, contains(401));
    });

    test('a declared response wins over the implied one', () {
      router
          .add(['POST'], '/books', handler)
          .body({'title': 'required'})
          .responds(const ApiSchema.none(), status: 422, description: 'Nope');

      final response = documentOf(
        router,
      ).operations.single.responses.singleWhere((r) => r.status == 422);
      expect(response.description, 'Nope');
    });

    test('successResponse skips errors and empty bodies', () {
      router
          .add(['DELETE'], '/books/{id}', handlerWithId)
          .responds(const ApiSchema.none(), status: 204);

      expect(documentOf(router).operations.single.successResponse, isNull);
    });
  });

  group('security', () {
    test('an auth alias requires the bearer scheme', () {
      router
          .add(['GET'], '/user', handler)
          .middleware(['auth:cartouche'])
          .responds(bookSchema);

      final security = documentOf(router).operations.single.security.single;
      expect(security.scheme, apiBearerScheme);
      expect(security.abilities, isEmpty);
      expect(documentOf(router).usesBearerAuth, isTrue);
    });

    test('ability aliases become sorted ability metadata', () {
      router
          .add(['POST'], '/books', handler)
          .middleware(['auth', 'abilities:books:write,books:read'])
          .responds(bookSchema);

      expect(documentOf(router).operations.single.security.single.abilities, [
        'books:read',
        'books:write',
      ]);
    });

    test('an unsecured route requires nothing', () {
      router
          .add(['GET'], '/books', handler)
          .middleware(['throttle:60,1'])
          .responds(bookSchema);

      expect(documentOf(router).operations.single.security, isEmpty);
      expect(documentOf(router).usesBearerAuth, isFalse);
    });
  });

  group('operation ids', () {
    test('a route name becomes a camelCase id', () {
      router.add(['GET'], '/books', handler).name('books.index').summary('L');

      expect(documentOf(router).operations.single.operationId, 'booksIndex');
    });

    test('an unnamed route falls back to its verb and path', () {
      router.add(['GET'], '/books/{id}/cover', handlerWithId).summary('C');

      expect(
        documentOf(router).operations.single.operationId,
        'getBooksByIdCover',
      );
    });

    test('an explicit id wins', () {
      router
          .add(['GET'], '/books', handler)
          .name('books.index')
          .operation('listBooks');

      expect(documentOf(router).operations.single.operationId, 'listBooks');
    });

    test('a second verb on one route gets its own id', () {
      // Route.resource registers update as PUT and PATCH together.
      router
          .add(['PUT', 'PATCH'], '/books/{id}', handlerWithId)
          .name('books.update')
          .responds(bookSchema);

      expect(documentOf(router).operations.map((o) => o.operationId), [
        'booksUpdate',
        'booksUpdatePatch',
      ]);
    });

    test('a collision names both routes rather than renaming one', () {
      router.add(['GET'], '/books', handler).operation('listBooks');
      router.add(['GET'], '/volumes', handler).operation('listBooks');

      expect(
        () => documentOf(router),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('/books'), contains('/volumes')),
          ),
        ),
      );
    });

    test('two contracts cannot silently overwrite one endpoint', () {
      router.add(['GET'], '/books', handler).operation('first');
      router.add(['GET'], '/books', handler).operation('second');

      expect(
        () => documentOf(router),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('GET /books'),
          ),
        ),
      );
    });
  });

  test('response statuses outside the HTTP range fail at declaration', () {
    final route = router.add(['GET'], '/books', handler);

    expect(() => route.responds(bookSchema, status: 42), throwsArgumentError);
    expect(() => route.responds(bookSchema, status: 600), throwsArgumentError);
  });

  group('schemas', () {
    test('named schemas are collected and sorted', () {
      router.add(['POST'], '/books', handler).name('books.store')
        ..body({'title': 'required|string'})
        ..responds(bookSchema, status: 201);

      expect(documentOf(router).schemas.keys, [
        'Book',
        'BooksStoreRequest',
        'ValidationError',
      ]);
    });

    test('nested named schemas are collected too', () {
      const author = ApiSchema.object({
        'name': ApiSchema.string(),
      }, name: 'Author');
      const withAuthor = ApiSchema.object({
        'id': ApiSchema.integer(),
        'author': author,
      }, name: 'Book');
      router.add(['GET'], '/books', handler).responds(withAuthor);

      expect(documentOf(router).schemas.keys, ['Author', 'Book']);
    });

    test('one name for two shapes is refused', () {
      const other = ApiSchema.object({
        'slug': ApiSchema.string(),
      }, name: 'Book');
      router.add(['GET'], '/books', handler).responds(bookSchema);
      router.add(['GET'], '/volumes', handler).responds(other);

      expect(
        () => documentOf(router),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('named [Book]'),
          ),
        ),
      );
    });

    test('nullable and non-nullable uses share one named component', () {
      router.add(['GET'], '/book', handler).responds(bookSchema);
      router.add(['GET'], '/maybe-book', handler).responds(bookSchema.nullable);

      expect(documentOf(router).schemas.keys.where((name) => name == 'Book'), [
        'Book',
      ]);
      expect(documentOf(router).schemas['Book']!.isNullable, isFalse);
    });

    test('nested differences under one schema name are refused', () {
      const first = ApiSchema.object({
        'profile': ApiSchema.object({'age': ApiSchema.integer(minimum: 1)}),
      }, name: 'User');
      const second = ApiSchema.object({
        'profile': ApiSchema.object({'age': ApiSchema.integer(minimum: 18)}),
      }, name: 'User');
      router.add(['GET'], '/young', handler).responds(first);
      router.add(['GET'], '/adult', handler).responds(second);

      expect(() => documentOf(router), throwsStateError);
    });
  });

  test('operations keep route registration order', () {
    router.add(['GET'], '/zeta', handler).summary('Z');
    router.add(['GET'], '/alpha', handler).summary('A');

    expect(documentOf(router).operations.map((o) => o.path), [
      '/zeta',
      '/alpha',
    ]);
  });
}
