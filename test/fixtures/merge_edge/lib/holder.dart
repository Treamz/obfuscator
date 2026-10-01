class Holder {
  Holder(this._value);

  final int? _value;

  int get doubled => _value != null ? _value * 2 : 0;
}
