import 'package:localdep/localdep.dart' hide Gadget;
import 'package:otherdep/otherdep.dart' show Gadget;

// `a.dart` imports `Gadget` of `localdep` as well, which isn't used anywhere.
List<String> lReport() => ['l ${Gadget().kind} $localCount'];
