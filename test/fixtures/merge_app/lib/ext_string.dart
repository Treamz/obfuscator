extension OnString on String {
  String describe() => 'string';

  String get label => 'string-label';
}

extension on String {
  Object self() => 'string-self';
}

List<String> extStringReport() => ['ext2 ${'y'.describe()} ${'y'.label} ${'y'.self()}'];
