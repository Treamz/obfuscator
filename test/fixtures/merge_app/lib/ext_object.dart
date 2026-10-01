extension OnObject on Object {
  String describe() => 'object';

  String get label => 'object-label';
}

extension on Object {
  Object self() => this;
}

// The extensions on `String` of `ext_string.dart` are not visible in this library.
List<String> extObjectReport() {
  const text = 'x';
  return ['ext ${text.describe()} ${text.label} ${text.self().describe()}'];
}
