// @dart=3.6
import 'dart:math' as _;

_ firstOf<_>(List<_> values) {
  final _ result = values.first;
  return result;
}

class LegacyBox<_> {
  LegacyBox(this.value);

  final _ value;
}

int biggestOf(List<int> values) => values.reduce(_.max);
