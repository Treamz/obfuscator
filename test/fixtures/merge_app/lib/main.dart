import 'a.dart';
import 'b.dart';
import 'c.dart';
import 'd.dart';
import 'e.dart';
import 'f.dart';
import 'deferred.dart';
import 'gen.dart';
import 'route.dart';

Future<void> main() async {
  for (final line in [...aReport(), ...bReport(), ...cReport(), ...dReport(), ...eReport(), ...fReport(), ...genReport(), ...routeReport(), await deferredValue()]) {
    print(line);
  }
}
