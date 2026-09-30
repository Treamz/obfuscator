extension Fmt on int {
  String fmt() => 'second:$this';
}

String fromSecond(int v) => Fmt(v).fmt();
