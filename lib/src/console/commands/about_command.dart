import 'dart:io';

import '../../config/config.dart';
import '../../foundation/application.dart';
import '../command.dart';

class AboutCommand extends Command {
  @override
  String get name => 'about';
  @override
  String get description => 'Display basic information about your application';

  @override
  Future<int> handle() async {
    table(
      ['Environment', ''],
      [
        ['Application Name', '${config('app.name') ?? ''}'],
        ['Maat Version', Application.version],
        ['Dart Version', Platform.version.split(' ').first],
        ['Environment', this.app.environment],
        ['Debug Mode', this.app.debug ? 'ENABLED' : 'OFF'],
        ['Base Path', this.app.basePath],
      ],
    );
    return 0;
  }
}
