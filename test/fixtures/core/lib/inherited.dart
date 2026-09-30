class CounterBase {
  int total = 1;
}

abstract class HasTotal {
  abstract int total;
}

// The field inherited from `CounterBase` implements the one of `HasTotal`.
class CounterImpl extends CounterBase implements HasTotal {}

List<String> inheritedReport() {
  final HasTotal counter = CounterImpl()..total += 4;
  return ['inherited ${counter.total} ${(counter as CounterBase).total}'];
}
