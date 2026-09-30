import 'box.dart';

class ConstBox implements Box {
  const ConstBox();

  @override
  int get value => 42;
}

enum EnumBox implements Box {
  only;

  @override
  int get value => 43;
}
