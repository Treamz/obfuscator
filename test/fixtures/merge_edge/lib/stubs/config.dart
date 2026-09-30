class Config {
  const Config([this._override]);

  final String? _override;

  String get value => _override ?? 'default';
}
