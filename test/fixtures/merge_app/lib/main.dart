import 'a.dart';
import 'api_export.dart';
import 'b.dart';
import 'c.dart';
import 'd.dart';
import 'e.dart';
import 'ext_object.dart';
import 'ext_string.dart';
import 'f.dart';
import 'g.dart';
import 'h.dart';
import 'iface_impl.dart';
import 'k.dart';
import 'l.dart';
import 'private_child.dart';
import 'proto.dart';
import 'deferred.dart';
import 'gen.dart';
import 'route.dart';

Future<void> main() async {
  for (final line in [...aReport(), ...apiExportReport(), ...bReport(), ...cReport(), ...dReport(), ...eReport(), ...extObjectReport(), ...extStringReport(), ...fReport(), ...await gReport(), ...hReport(), ...ifaceReport(), ...kReport(), ...lReport(), ...privateReport(), ...protoReport(), ...genReport(), ...routeReport(), await deferredValue()]) {
    print(line);
  }
}
