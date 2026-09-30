import 'a.dart';
import 'api_export.dart';
import 'b.dart';
import 'c.dart';
import 'd.dart';
import 'e.dart';
import 'f.dart';
import 'g.dart';
import 'h.dart';
import 'k.dart';
import 'private_child.dart';
import 'proto.dart';
import 'deferred.dart';
import 'gen.dart';
import 'route.dart';

Future<void> main() async {
  for (final line in [...aReport(), ...apiExportReport(), ...bReport(), ...cReport(), ...dReport(), ...eReport(), ...fReport(), ...await gReport(), ...hReport(), ...kReport(), ...privateReport(), ...protoReport(), ...genReport(), ...routeReport(), await deferredValue()]) {
    print(line);
  }
}
