import 'dyn_base.dart';

class DynChild extends DynBase {
  String _secret() => 'child';
}

String probe(Object o) {
  try {
    return (o as dynamic)._secret() as String;
  } on NoSuchMethodError {
    return 'none';
  }
}

List<String> dynamicReport() => ['dynamic ${probe(DynChild())} ${probe(DynBase())} ${DynChild().callBase()}'];
