import 'package:otherdep/otherdep.dart' as dep;
import 'package:otherdep/otherdep.dart' as lazy_dep;

// ignore: non_constant_identifier_names
String HashSet() => 'first-party';

List<String> hReport() => ['h ${dep.Widget().kind} ${lazy_dep.Widget().kind} ${HashSet()}'];
