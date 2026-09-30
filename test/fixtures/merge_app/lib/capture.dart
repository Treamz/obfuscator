import 'capture_helpers.dart' as helpers;

class Describer {
  // Without the prefix, `describeValue` would refer to this method.
  static String describeValue(int value) => helpers.describeValue(value);
}

String render() {
  const describeValue = 'local';
  return '${helpers.describeValue(1)} $describeValue';
}

List<String> captureReport() => ['capture ${Describer.describeValue(5)} ${render()}'];
