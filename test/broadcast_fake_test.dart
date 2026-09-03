import 'package:maat/maat.dart';
import 'package:maat/testing.dart';
import 'package:test/test.dart';

void main() {
  final assertionFailure = throwsA(isA<TestClientAssertionError>());

  test('records immutable broadcasts and filters assertions', () async {
    final fake = BroadcastFake();
    await fake.broadcast(['orders'], 'Shipped', {'id': 7});

    fake.assertBroadcasted('Shipped');
    fake.assertBroadcasted('Shipped', (sent) => sent.payload['id'] == 7);
    fake.assertBroadcastedTimes('Shipped', 1);
    fake.assertNotBroadcasted('Failed');
  });

  test('assertions throw TestClientAssertionError on mismatches', () {
    final fake = BroadcastFake();

    expect(() => fake.assertBroadcasted('Shipped'), assertionFailure);
    expect(() => fake.assertBroadcastedTimes('Shipped', 1), assertionFailure);
    expect(
      () => fake.assertNotBroadcasted('Shipped'),
      isNot(throwsA(anything)),
    );

    fake.broadcast(['orders'], 'Shipped', const {});

    expect(() => fake.assertNotBroadcasted('Shipped'), assertionFailure);
    expect(() => fake.assertNothingBroadcasted(), assertionFailure);
  });
}
