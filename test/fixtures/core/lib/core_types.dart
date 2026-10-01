class MyError extends Error {
  MyError(this.stackTrace);

  @override
  final StackTrace? stackTrace;
}

class Money {
  Money(this.hashCode);

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) => other is Money && other.hashCode == hashCode;
}

List<String> coreTypesReport() {
  final Error error = MyError(StackTrace.empty);
  return ['error ${error.stackTrace == StackTrace.empty}', 'money ${Money(5) == Money(5)} ${{Money(5), Money(5)}.length}'];
}
