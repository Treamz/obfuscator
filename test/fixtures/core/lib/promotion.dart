class Account {
  Account(this._balance);

  final int? _balance;

  // `_balance` can't be promoted, as `Legacy` declares a getter with the same name in this library.
  String describe() {
    if (_balance != null) {
      final history = [_balance];
      return '${history.runtimeType}';
    }
    return 'none';
  }
}

class Legacy {
  int? get _balance => null;

  int? peek() => _balance;
}

class Tagged2 {
  Tagged2({required this.tagId});

  final int tagId;
}

final Map<String, Function> builders = {'tagged': Tagged2.new};

List<String> promotionReport() => [
  'promotion ${Account(5).describe()} ${Legacy().peek()}',
  'builders ${(builders['tagged']!(tagId: 7) as Tagged2).tagId}',
];
