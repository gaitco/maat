import '../support/str.dart';

/// Code templates for `make:*` commands.
abstract final class Stubs {
  static String controller(String className) =>
      '''
import 'package:maat/maat.dart';

class $className extends Controller {}
''';

  static String invokableController(String className) =>
      '''
import 'dart:async';

import 'package:maat/maat.dart';

class $className extends Controller {
  /// Handle the incoming request.
  FutureOr<Object?> call(Request request) {
    return Response.noContent();
  }
}
''';

  static String apiController(String className) =>
      '''
import 'dart:async';

import 'package:maat/maat.dart';

class $className extends ResourceController {
  /// Display a listing of the resource.
  @override
  FutureOr<Object?> index(Request request) {
    return [];
  }

  /// Store a newly created resource.
  @override
  FutureOr<Object?> store(Request request) {
    return Response.noContent();
  }

  /// Display the specified resource.
  @override
  FutureOr<Object?> show(Request request, String id) {
    return {'id': id};
  }

  /// Update the specified resource.
  @override
  FutureOr<Object?> update(Request request, String id) {
    return {'id': id};
  }

  /// Remove the specified resource.
  @override
  FutureOr<Object?> destroy(Request request, String id) {
    return Response.noContent();
  }
}
''';

  static String middleware(String className) =>
      '''
import 'dart:async';

import 'package:maat/maat.dart';

class $className extends Middleware {
  /// Handle an incoming request.
  @override
  FutureOr<Response> handle(Request request, Next next) {
    return next(request);
  }
}
''';

  static String request(String className) =>
      '''
import 'package:maat/maat.dart';

class $className extends FormRequest {
  /// Determine if the user is authorized to make this request.
  @override
  bool authorize(Request request) {
    return true;
  }

  /// Get the validation rules that apply to the request.
  @override
  Map<String, Object> rules() {
    return {};
  }
}
''';

  static String provider(String className) =>
      '''
import 'package:maat/maat.dart';

class $className extends ServiceProvider {
  $className(super.app);

  /// Register any application services.
  @override
  void register() {}

  /// Bootstrap any application services.
  @override
  Future<void> boot() async {}
}
''';

  static String command(String className, String commandName) =>
      '''
import 'package:maat/maat.dart';

class $className extends Command {
  /// The name and signature of the console command.
  @override
  String get name => '$commandName';

  @override
  String get signature => '';

  /// The console command description.
  @override
  String get description => 'Command description';

  /// Execute the console command.
  @override
  Future<int> handle() async {
    info('$className ran.');
    return 0;
  }
}
''';

  static String event(String className) =>
      '''
import 'package:maat/maat.dart';

class $className with Dispatchable {
  $className();
}
''';

  static String listener(String className, String? eventClass) {
    final event = eventClass ?? 'Object';
    final eventImport = eventClass == null
        ? ''
        : "\nimport '../events/${Str.snake(eventClass)}.dart';\n";
    return '''
import 'package:maat/maat.dart';
$eventImport
class $className extends Listener<$event> {
  @override
  Future<void> handle($event event) async {}
}
''';
  }
}
