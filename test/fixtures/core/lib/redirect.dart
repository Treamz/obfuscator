abstract class Token {
  const factory Token({required String value}) = _TokenImpl;

  String get text;
}

class _TokenImpl implements Token {
  const _TokenImpl({required this.value});

  final String value;

  @override
  String get text => value;
}

List<String> redirectReport() => ['token ${const Token(value: 'v').text}'];
