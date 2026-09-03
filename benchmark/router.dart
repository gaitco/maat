import 'package:maat/maat.dart';

void main() {
  const iterations = 20000;
  for (final count in [1, 100, 1000]) {
    final router = Router();
    for (var i = 0; i < count; i++) {
      router.add(['GET'], '/route-$i', (Request request) => i);
    }
    final path = '/route-${count - 1}';
    for (var i = 0; i < 1000; i++) {
      assert(router.match('GET', path).route.uri == path);
    }

    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      router.match('GET', path);
    }
    watch.stop();
    final microseconds = watch.elapsedMicroseconds / iterations;
    print('$count routes: ${microseconds.toStringAsFixed(2)} us/match');
  }
}
