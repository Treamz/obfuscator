class Widget {
  String get kind => 'local';
}

class Gadget {
  String get kind => 'local-gadget';
}

int localCount = 3;

extension SharedX on String {
  String sharedShout() => 'local:$this';
}
