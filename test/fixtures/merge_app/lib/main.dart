import 'a.dart';
import 'b.dart';
import 'c.dart';
import 'deferred.dart';
import 'gen.dart';
import 'route.dart';

Future<void> main() async {
  for (final line in [...aReport(), ...bReport(), ...cReport(), ...genReport(), ...routeReport(), await deferredValue()]) {
    print(line);
  }
}
