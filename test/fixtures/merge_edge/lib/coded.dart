abstract class Coded {
  String get code;

  void _internal();
}

String describeCode(Coded coded) => 'code=${coded.code}';

abstract class Store {
  int _count = 0;

  int get count => _count;
}

class StoreBase {
  int get _count => 42;
}

class Node {
  Node(this._label);

  final String? _label;

  int get size {
    if (_label != null) return _label.length;
    return 0;
  }
}
