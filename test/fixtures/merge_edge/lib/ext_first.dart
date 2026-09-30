extension Shout on String {
  String shout() => '${toUpperCase()}!';
}

extension Fmt on int {
  String fmt() => 'first:$this';
}

String fromFirst(int v) => Fmt(v).fmt();
