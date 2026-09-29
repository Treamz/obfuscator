class Base {
  final String label = 'base';

  String describe() => label;
}

class Child extends Base {
  // ignore: annotate_overrides, overridden_fields
  final String label = 'child';
}

class Holder {
  int value = 1;
}

class ComputedHolder extends Holder {
  @override
  int get value => 42;

  @override
  set value(int newValue) {}
}

List<String> overridesReport() {
  final Base base = Child();
  final Holder holder = ComputedHolder();
  return ['describe ${Child().describe()}', 'base ${base.label}', 'holder ${holder.value}'];
}
