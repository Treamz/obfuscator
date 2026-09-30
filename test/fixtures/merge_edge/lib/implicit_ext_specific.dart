import 'implicit_ext.dart';

extension OnThing on Thing {
  String kindName() => 'specific';
}

List<String> implicitReport() => ['implicit ${Thing().report()} ${Thing().kindName()}'];
