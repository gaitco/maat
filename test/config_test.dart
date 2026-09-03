import 'package:maat/maat.dart';
import 'package:test/test.dart';

void main() {
  late Config cfg;
  setUp(() {
    cfg = Config({
      'app': {
        'name': 'Maat',
        'debug': true,
        'nested': {'deep': 1},
      },
      'cors': {
        'origins': ['*'],
      },
    });
    Config.current = cfg;
  });

  test('get resolves dot paths', () {
    expect(cfg.get('app.name'), 'Maat');
    expect(cfg.get('app.nested.deep'), 1);
    expect(cfg.get('cors.origins'), ['*']);
    expect(cfg.get('app'), isA<Map>());
  });

  test('get returns default for missing', () {
    expect(cfg.get('app.missing'), isNull);
    expect(cfg.get('app.missing', 'x'), 'x');
    expect(cfg.get('nope.at.all', 3), 3);
  });

  test('set writes dot paths creating maps', () {
    cfg.set('app.name', 'Other');
    cfg.set('new.section.key', true);
    expect(cfg.get('app.name'), 'Other');
    expect(cfg.get('new.section.key'), isTrue);
  });

  test('has', () {
    expect(cfg.has('app.debug'), isTrue);
    expect(cfg.has('app.nothing'), isFalse);
  });

  test('config helper reads Config.current', () {
    expect(config('app.name'), 'Maat');
    expect(config('x.y', 'd'), 'd');
  });
}
