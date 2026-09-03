import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  group('Str', () {
    test('snake converts PascalCase and camelCase', () {
      expect(Str.snake('PostController'), 'post_controller');
      expect(Str.snake('userProfile'), 'user_profile');
      expect(Str.snake('HTTPServer'), 'h_t_t_p_server');
      expect(Str.snake('already_snake'), 'already_snake');
      expect(Str.snake('with space'), 'with_space');
    });

    test('studly converts snake, kebab and spaces', () {
      expect(Str.studly('post_controller'), 'PostController');
      expect(Str.studly('post-controller'), 'PostController');
      expect(Str.studly('post controller'), 'PostController');
      expect(Str.studly('PostController'), 'PostController');
    });

    test('kebab', () {
      expect(Str.kebab('PostController'), 'post-controller');
    });

    test('headline turns class and snake names into words', () {
      expect(Str.headline('OrderShipped'), 'Order Shipped');
      expect(Str.headline('password_reset'), 'Password Reset');
    });

    test('uuid returns distinct RFC 4122 version 4 values', () {
      final first = Str.uuid();
      final second = Str.uuid();
      expect(first, isNot(second));
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });
}
