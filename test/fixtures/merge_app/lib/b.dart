library my.lib;

import "package:otherdep/otherdep.dart";

export "src/helpers.dart";

part "b_part.dart";

List<String> bReport() => ['b ${Widget().kind} ${partValue()}'];
