import 'src/barrel.dart';
import 'src/barrel.dart' as ui;

export 'src/barrel.dart';

List<String> dReport() {
  final queue = Queue<int>()..addAll([1, 2]);
  final map = ui.SplayTreeMap<String, int>()..['k'] = 5;
  return ['d ${queue.length} ${map['k']}'];
}
