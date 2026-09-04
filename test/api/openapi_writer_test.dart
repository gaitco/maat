import 'dart:convert';

import 'package:maat/src/api/api_document.dart';
import 'package:maat/src/api/openapi_writer.dart';
import 'package:maat/src/api/schema.dart';
import 'package:maat/src/http/request.dart';
import 'package:maat/src/routing/router.dart';
import 'package:test/test.dart';

Object? handler(Request request) => null;
Object? handlerWithId(Request request, String id) => null;

// Composed with `.nullable`, so it is `final` rather than `const`.
final bookSchema = ApiSchema.object({
  'id': ApiSchema.integer(),
  'title': ApiSchema.string(),
  'subtitle': ApiSchema.string().nullable,
  'tags': ApiSchema.array(ApiSchema.string()),
}, name: 'Book');

Router fixtureRouter() {
  final router = Router();
  router
      .add(['GET', 'HEAD'], '/api/books', handler)
      .name('books.index')
      .summary('List books')
      .query({'q': 'string|max:50'})
      .responds(ApiSchema.array(bookSchema));
  router
      .add(['POST'], '/api/books', handler)
      .name('books.store')
      .middleware(['auth:cartouche', 'ability:books:write'])
      .summary('Create a book')
      .body({'title': 'required|string|max:120'})
      .responds(bookSchema, status: 201);
  router
      .add(['GET', 'HEAD'], '/api/books/{id}', handlerWithId)
      .name('books.show')
      .params({'id': 'required|integer'})
      .summary('Show a book')
      .responds(bookSchema)
      .responds(apiErrorSchema, status: 404);
  return router;
}

Map<String, Object?> documentJson([Router? router]) => OpenApiWriter(
  ApiDocument.fromRouter(
    router ?? fixtureRouter(),
    info: const ApiInfo(title: 'Catalog', version: '1.0.0'),
    servers: const [ApiServer('https://example.test/api')],
  ),
).toJson();

void main() {
  test('the document is a complete OpenAPI 3.1 description', () {
    expect(documentJson(), {
      'openapi': '3.1.0',
      'info': {'title': 'Catalog', 'version': '1.0.0'},
      'servers': [
        {'url': 'https://example.test/api'},
      ],
      'paths': {
        '/api/books': {
          'get': {
            'operationId': 'booksIndex',
            'summary': 'List books',
            'parameters': [
              {
                'name': 'q',
                'in': 'query',
                'required': false,
                'schema': {'type': 'string', 'maxLength': 50},
              },
            ],
            'responses': {
              '200': {
                'description': 'OK',
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'array',
                      'items': {r'$ref': '#/components/schemas/Book'},
                    },
                  },
                },
              },
              '422': {
                'description': 'The given data was invalid.',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/ValidationError'},
                  },
                },
              },
            },
          },
          'post': {
            'operationId': 'booksStore',
            'summary': 'Create a book',
            'requestBody': {
              'required': true,
              'content': {
                'application/json': {
                  'schema': {r'$ref': '#/components/schemas/BooksStoreRequest'},
                },
              },
            },
            'responses': {
              '201': {
                'description': 'Created',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/Book'},
                  },
                },
              },
              '401': {
                'description': 'Unauthenticated.',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/ErrorResponse'},
                  },
                },
              },
              '422': {
                'description': 'The given data was invalid.',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/ValidationError'},
                  },
                },
              },
            },
            'security': [
              {'bearerAuth': <String>[]},
            ],
            'x-maat-abilities': ['books:write'],
          },
        },
        '/api/books/{id}': {
          'get': {
            'operationId': 'booksShow',
            'summary': 'Show a book',
            'parameters': [
              {
                'name': 'id',
                'in': 'path',
                'required': true,
                'schema': {'type': 'integer'},
              },
            ],
            'responses': {
              '200': {
                'description': 'OK',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/Book'},
                  },
                },
              },
              '404': {
                'description': 'Not found',
                'content': {
                  'application/json': {
                    'schema': {r'$ref': '#/components/schemas/ErrorResponse'},
                  },
                },
              },
            },
          },
        },
      },
      'components': {
        'schemas': {
          'Book': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'title': {'type': 'string'},
              'subtitle': {
                'type': ['string', 'null'],
              },
              'tags': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'required': ['id', 'title', 'subtitle', 'tags'],
          },
          'BooksStoreRequest': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'maxLength': 120},
            },
            'required': ['title'],
          },
          'ErrorResponse': {
            'type': 'object',
            'properties': {
              'message': {'type': 'string'},
            },
            'required': ['message'],
          },
          'ValidationError': {
            'type': 'object',
            'properties': {
              'message': {'type': 'string'},
              'errors': {'type': 'object', 'properties': {}},
            },
            'required': ['message', 'errors'],
          },
        },
        'securitySchemes': {
          'bearerAuth': {
            'type': 'http',
            'scheme': 'bearer',
            'description':
                'A Cartouche personal access token, sent as '
                '`Authorization: Bearer <token>`.',
          },
        },
      },
    });
  });

  test('paths are sorted and verbs follow the OpenAPI order', () {
    final router = Router();
    router.add(['PATCH'], '/zeta', handler).summary('Z');
    router.add(['GET'], '/zeta', handler).summary('G');
    router.add(['POST'], '/alpha', handler).summary('A');

    final paths = documentJson(router)['paths']! as Map<String, Object?>;
    expect(paths.keys, ['/alpha', '/zeta']);
    expect((paths['/zeta']! as Map).keys, ['get', 'patch']);
  });

  test('the same document renders byte for byte the same twice', () {
    final first = OpenApiWriter(
      ApiDocument.fromRouter(
        fixtureRouter(),
        info: const ApiInfo(title: 'Catalog', version: '1.0.0'),
      ),
    ).toPrettyJson();
    final second = OpenApiWriter(
      ApiDocument.fromRouter(
        fixtureRouter(),
        info: const ApiInfo(title: 'Catalog', version: '1.0.0'),
      ),
    ).toPrettyJson();

    expect(first, second);
    expect(first, endsWith('\n'));
    expect(jsonDecode(first), isA<Map<String, Object?>>());
  });

  test('a nullable reference is a oneOf rather than a sibling of the ref', () {
    final router = Router();
    router
        .add(['GET'], '/books', handler)
        .responds(
          ApiSchema.object({
            'book': bookSchema,
            'next': bookSchema.nullable,
          }, name: 'Wrapper'),
        );

    final properties =
        (((documentJson(router)['components']! as Map)['schemas']!
                    as Map)['Wrapper']!
                as Map)['properties']!
            as Map;
    expect(properties['book'], {r'$ref': '#/components/schemas/Book'});
    // A `$ref` with siblings is honoured by only some 3.1 tooling, so the
    // nullable case is spelled out as a union instead.
    expect(properties['next'], {
      'oneOf': [
        {r'$ref': '#/components/schemas/Book'},
        {'type': 'null'},
      ],
    });
  });

  test('every ref points at a schema the document defines', () {
    final json = documentJson();
    final defined = ((json['components']! as Map)['schemas']! as Map).keys
        .toSet();
    final refs = RegExp(
      r'#/components/schemas/(\w+)',
    ).allMatches(jsonEncode(json)).map((m) => m[1]!).toSet();

    expect(refs, isNotEmpty);
    expect(refs.difference(defined), isEmpty);
  });
}
