import 'package:localdep/localdep.dart' as dep;
import 'package:localdep/localdep.dart' deferred as lazy_dep hide SharedX;

Future<List<String>> gReport() async {
  await lazy_dep.loadLibrary();
  return ['g ${dep.Widget().kind} ${lazy_dep.Widget().kind}'];
}
