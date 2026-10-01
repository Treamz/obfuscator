class Counted {
  Counted({required this.count});

  final int count;
}

mixin Loud {
  String shout() => 'LOUD';
}

class LoudCounted = Counted with Loud;

List<String> aliasReport() {
  final value = LoudCounted(count: 3);
  return ['alias ctor ${value.count} ${value.shout()}'];
}
