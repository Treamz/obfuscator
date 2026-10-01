import 'cursor.dart';

class Walker extends Cursor {
  int walk(List<int> values) {
    var sum = 0;
    for (current in values) {
      sum += current;
    }
    return sum;
  }
}
