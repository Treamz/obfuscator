extension on String {
  String capitalize() => toUpperCase();

  String get initials => 'x';
}

extension on String? {
  String orDash() => 'other';
}

String badge(String label) => '[${label.capitalize()} ${label.initials}] ${null.orDash()}';
