import 'coded.dart';

enum Level implements Coded {
  low,
  high;

  @override
  String get code => name.toUpperCase();
}

mixin CodeMixin {
  String get code => 'mixed';
}

class CodedAlias = Object with CodeMixin implements Coded;

class StoreImpl extends StoreBase implements Store {
  @override
  int get count => 1;
}

class FakeNode implements Node {
  @override
  int get size => -1;
}

List<String> codedReport() => [
  'coded ${describeCode(Level.high)} ${describeCode(CodedAlias())} ${StoreImpl().count} ${Node('abc').size} ${FakeNode().size}',
];
