import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../command.dart';

class KeyGenerateCommand extends Command {
  @override
  String get name => 'key:generate';
  @override
  String get description => 'Set the application key';
  @override
  String get signature => '{--show}';

  @override
  Future<int> handle() async {
    final key = generateKey();
    if (flag('show')) {
      info(key);
      return 0;
    }
    final file = File(app.path('.env'));
    final contents = file.existsSync() ? file.readAsStringSync() : '';
    final pattern = RegExp(r'^APP_KEY=.*$', multiLine: true);
    final updated = pattern.hasMatch(contents)
        ? contents.replaceFirst(pattern, 'APP_KEY=$key')
        : '${contents.isEmpty || contents.endsWith('\n') ? contents : '$contents\n'}APP_KEY=$key\n';
    file.writeAsStringSync(updated);
    info('Application key set successfully.');
    return 0;
  }

  static String generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return 'base64:${base64Encode(bytes)}';
  }
}
