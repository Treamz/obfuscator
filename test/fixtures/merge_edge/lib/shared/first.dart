extension SharedX on String {
  String sharedShout() => 'first:$this';
}

String sharedFirst(String value) => value.sharedShout();
