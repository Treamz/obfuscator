mixin Pretty on Enum {
  @override
  String toString() => 'pretty $index';
}

enum Grade with Pretty { high }
