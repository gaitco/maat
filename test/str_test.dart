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
  });
}
