import 'switch_values.dart' as values;

List<String> switchReport() => [
  for (final n in [1, 2])
    switch (n) {
      1 => _local(),
      _ => 'switch ${values.edgeValue}',
    },
  _caseBody(1),
];

String _local() => 'switch local';

String _caseBody(int n) {
  switch (n) {
    case 1:
      final edgeValue = 'case-local';
      return 'switch $edgeValue ${values.edgeValue}';
    default:
      return values.edgeValue;
  }
}
