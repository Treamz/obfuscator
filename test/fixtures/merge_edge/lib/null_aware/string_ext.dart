extension StringX on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  String get initials => split(' ').map((word) => word[0]).join();
}

extension OrDash on String? {
  String orDash() => this ?? '-';
}
