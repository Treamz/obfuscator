abstract class Parser {
  bool get _strict;

  String _name() => 'parser';

  String parse();

  String describe() => _name();
}

bool strictOf(Parser parser) => parser._strict;
