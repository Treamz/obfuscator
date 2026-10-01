abstract class Frame {
  int get position => 3;
}

class FrameImpl extends Frame {
  // `position` is the inherited getter, the top-level `position` of `position.dart` isn't visible here.
  String describe() => '${'*' * (1 + position)} $position';
}

List<String> frameReport() => ['frame ${FrameImpl().describe()}'];
