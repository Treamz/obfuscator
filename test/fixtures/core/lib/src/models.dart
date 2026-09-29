/// A [Box] holding a [Box.content] value.
class Box<T> {
  Box(this.content);

  T content;

  static int created = 0;
}

mixin Tracked {
  int trackedCount = 0;
}

class TrackedBox extends Box<String> with Tracked {
  TrackedBox(super.content);
}

class AliasBase {
  final int aliasValue = 9;
}

mixin AliasMixin {}

class Alias = AliasBase with AliasMixin;

enum Level {
  low(1),
  high(2);

  const Level(this.weight);

  final int weight;
}

typedef BoxOfInt = Box<int>;

extension BoxDescription on Box<Object?> {
  String get description => 'box($content)';
}
