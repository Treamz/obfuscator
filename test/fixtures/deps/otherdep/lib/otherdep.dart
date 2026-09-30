class Widget {
  String get kind => 'other';
}

class Gadget {
  String get kind => 'other-gadget';
}

extension SharedX on String {
  String sharedShout() => 'other:$this';
}
