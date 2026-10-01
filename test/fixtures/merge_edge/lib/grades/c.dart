enum Grade {
  mid('Middle');

  const Grade(this.label);

  final String label;

  String get name => label.toUpperCase();
}
