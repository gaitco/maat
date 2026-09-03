import '../../routing/router.dart';
import '../command.dart';

class RouteListCommand extends Command {
  @override
  String get name => 'route:list';
  @override
  String get description => 'List all registered routes';

  @override
  Future<int> handle() async {
    final rows = <List<String>>[];
    for (final route in app.make<Router>().routes) {
      rows.add([
        route.methods.where((m) => m != 'HEAD').join('|'),
        route.uri,
        route.routeName ?? '',
        route.middlewareList
            .map((m) => m is String ? m : m.runtimeType.toString())
            .join(', '),
      ]);
    }
    table(['Method', 'URI', 'Name', 'Middleware'], rows);
    info('\nShowing ${rows.length} routes');
    return 0;
  }
}
