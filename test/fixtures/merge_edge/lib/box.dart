class Box {
  Box(this._value);

  final int? _value;

  int get value => _value != null ? _value + 1 : 0;
}
