import 'package:maat/src/api/api_document.dart';
import 'package:maat/src/api/dart_client_writer.dart';
import 'package:maat/src/api/schema.dart';
import 'package:maat/src/http/request.dart';
import 'package:maat/src/routing/router.dart';
import 'package:test/test.dart';

Object? handler(Request request) => null;
Object? handlerWithId(Request request, String id) => null;

final bookSchema = ApiSchema.object({
  'id': ApiSchema.integer(),
  'title': ApiSchema.string(),
  'subtitle': ApiSchema.string().nullable,
  'parent_id': ApiSchema.integer().optional,
  'tags': ApiSchema.array(ApiSchema.string()),
  'published_at': ApiSchema.string(format: 'date-time'),
}, name: 'Book');

String sourceFor(Router router, {String className = 'CatalogClient'}) =>
    DartClientWriter(
      ApiDocument.fromRouter(
        router,
        info: const ApiInfo(title: 'Catalog', version: '1.0.0'),
      ),
      className: className,
    ).toSource();

void main() {
  test('a DTO is emitted for every schema a client sends or decodes', () {
    final router = Router();
    router
        .add(['GET'], '/books/{id}', handlerWithId)
        .name('books.show')
        .responds(bookSchema);

    final source = sourceFor(router);
    expect(source, contains('final class BookDto {'));
    expect(source, contains('  final int id;'));
    expect(source, contains('  final String title;'));
    expect(source, contains('  final String? subtitle;'));
    expect(source, contains('  final int? parentId;'));
    expect(source, contains('  final List<String> tags;'));
    expect(source, contains('  final DateTime publishedAt;'));
  });

  test('error schemas do not become DTOs', () {
    final router = Router();
    router
        .add(['GET'], '/books/{id}', handlerWithId)
        .responds(bookSchema)
        .responds(apiErrorSchema, status: 404);

    // Errors surface as HorusClientException, so a class for them would be
    // code nothing can reach.
    expect(sourceFor(router), isNot(contains('ErrorResponseDto')));
  });

  group('decoding', () {
    late String source;

    setUp(() {
      final router = Router();
      router
          .add(['GET'], '/books/{id}', handlerWithId)
          .name('books.show')
          .responds(bookSchema);
      source = sourceFor(router);
    });

    test('a nullable field decodes through a null check', () {
      expect(
        source,
        contains(
          "subtitle: json['subtitle'] == null "
          "? null : json['subtitle']! as String,",
        ),
      );
    });

    test('a list decodes element by element', () {
      expect(
        source,
        contains(
          "tags: [for (final item in json['tags']! as List<Object?>) "
          'item! as String],',
        ),
      );
    });

    test('a date-time field becomes a DateTime', () {
      expect(
        source,
        contains(
          "publishedAt: DateTime.parse(json['published_at']! as String)",
        ),
      );
    });

    test('an optional field is left out of toJson when null', () {
      expect(source, contains("if (parentId != null) 'parent_id': parentId,"));
      expect(source, contains("'title': title,"));
    });

    test('a date-time field is written back as ISO-8601', () {
      expect(
        source,
        contains("'published_at': publishedAt.toIso8601String(),"),
      );
    });
  });

  group('methods', () {
    test('a path parameter becomes a required named argument', () {
      final router = Router();
      router
          .add(['GET'], '/books/{id}', handlerWithId)
          .name('books.show')
          .params({'id': 'required|integer'})
          .responds(bookSchema);

      expect(
        sourceFor(router),
        contains('Future<BookDto> booksShow({required int id}) =>'),
      );
      expect(
        sourceFor(router),
        contains("_client.send(_booksShow, pathParameters: {'id': id});"),
      );
    });

    test('query parameters are optional named arguments', () {
      final router = Router();
      router
          .add(['GET'], '/books', handler)
          .name('books.index')
          .query({'q': 'string', 'per_page': 'integer'})
          .responds(ApiSchema.array(bookSchema));

      final source = sourceFor(router);
      expect(
        source,
        contains(
          'Future<List<BookDto>> booksIndex({String? q, int? perPage}) =>',
        ),
      );
      expect(
        source,
        contains("queryParameters: {'q': q, 'per_page': perPage}"),
      );
    });

    test('a request body becomes a generated DTO argument', () {
      final router = Router();
      router
          .add(['POST'], '/books', handler)
          .name('books.store')
          .body({'title': 'required|string'})
          .responds(bookSchema, status: 201);

      final source = sourceFor(router);
      expect(source, contains('final class BooksStoreRequestDto {'));
      expect(
        source,
        contains(
          'Future<BookDto> booksStore('
          '{required BooksStoreRequestDto body}) =>',
        ),
      );
      expect(source, contains('body: body.toJson()'));
    });

    test('an empty response gives a Future<void>', () {
      final router = Router();
      router
          .add(['DELETE'], '/books/{id}', handlerWithId)
          .name('books.destroy')
          .responds(const ApiSchema.none(), status: 204);

      final source = sourceFor(router);
      expect(source, contains('final _booksDestroy = Endpoint<void>('));
      expect(source, contains('decode: (json) {},'));
      expect(
        source,
        contains('Future<void> booksDestroy({required String id})'),
      );
    });

    test('the summary and the auth requirement reach the doc comment', () {
      final router = Router();
      router
          .add(['POST'], '/books', handler)
          .name('books.store')
          .middleware(['auth', 'ability:books:write'])
          .summary('Create a book')
          .responds(bookSchema, status: 201);

      final source = sourceFor(router);
      expect(source, contains('/// Create a book'));
      expect(
        source,
        contains(
          '/// `POST /books` — requires a bearer token with books:write.',
        ),
      );
    });

    test('a name that collides with a Dart keyword is escaped', () {
      final router = Router();
      router
          .add(['GET'], '/books', handler)
          .name('books.index')
          .query({'class': 'string'})
          .responds(ApiSchema.array(bookSchema));

      final source = sourceFor(router);
      expect(source, contains('{String? class_}'));
      expect(source, contains("queryParameters: {'class': class_}"));
    });
  });

  test('the client class is named as asked', () {
    final router = Router();
    router.add(['GET'], '/books', handler).responds(bookSchema);

    expect(
      sourceFor(router, className: 'Books'),
      contains('final class Books {'),
    );
  });

  test('an invalid Dart operation id fails with an actionable message', () {
    final router = Router();
    router
        .add(['GET'], '/two-factor', handler)
        .operation('2faVerify')
        .responds(bookSchema);

    expect(
      () => sourceFor(router),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('operation id'), contains('lowerCamelCase')),
        ),
      ),
    );
  });

  test('body and query parameters cannot generate the same Dart name', () {
    final router = Router();
    router
        .add(['POST'], '/books', handler)
        .name('books.store')
        .query({'body': 'string'})
        .body({'title': 'required|string'})
        .responds(bookSchema);

    expect(() => sourceFor(router), throwsStateError);
  });

  test('wire names are escaped in generated Dart string literals', () {
    final router = Router();
    router
        .add(['GET'], "/author's-books", handler)
        .name('books.index')
        .responds(bookSchema);

    expect(sourceFor(router), contains(r'''path: "/author's-books"'''));
  });

  test('the same document generates byte for byte the same source', () {
    Router build() {
      final router = Router();
      router
          .add(['GET'], '/books', handler)
          .name('books.index')
          .query({'q': 'string'})
          .responds(ApiSchema.array(bookSchema));
      router
          .add(['POST'], '/books', handler)
          .name('books.store')
          .body({'title': 'required|string'})
          .responds(bookSchema, status: 201);
      return router;
    }

    expect(sourceFor(build()), sourceFor(build()));
  });
}
