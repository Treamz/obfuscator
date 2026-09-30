import 'iface.dart';

// The private members of `Parser` are declared by another library, so they don't have to be implemented.
class AnyParser implements Parser {
  @override
  String parse() => 'any';

  @override
  String describe() => 'any-parser';
}

List<String> ifaceReport() {
  final parser = AnyParser();
  String error;
  try {
    strictOf(parser);
    error = 'none';
  } on NoSuchMethodError {
    error = 'no-such-method';
  }
  return ['iface ${parser.parse()} ${parser.describe()} $error'];
}
