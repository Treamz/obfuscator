import 'modes.dart' as modes;

typedef Pick<Mode> = modes.Mode Function(Mode value);

String pickReport() {
  final Pick<int> pick = (int value) => modes.Mode.values[value];
  return 'pick ${pick(1)}';
}
