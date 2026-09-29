import 'package:core/src/models.dart' show Box, TrackedBox, Alias, Level, BoxOfInt, BoxDescription;

List<String> miscReport() {
  Box.created++;
  final box = TrackedBox('a')
    ..content = 'b'
    ..trackedCount += 2;
  box.content += 'c';
  final BoxOfInt ints = Box(1);
  ints.content++;
  final factory = Box<int>.new;
  Level level = .high;
  final Object any = box;
  return [
    'box ${box.content} ${box.trackedCount} ${Box.created}',
    'ints ${ints.content} ${factory(4).content}',
    'level ${level.weight} ${Level.low.weight}',
    'alias ${Alias().aliasValue}',
    'is ${any is Box<String>} ${(any as Box).description}',
  ];
}
