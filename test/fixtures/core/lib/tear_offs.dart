class Built {
  Built({required this.builtId});

  final int builtId;
}

class Runner2 {
  Runner2({required this.target});

  final String target;
}

typedef BuiltFactory = Built Function({required int builtId});

final BuiltFactory builtFactory = Built.new;

List<String> tearOffsReport() {
  final runner = (switch (1) { _ => Runner2.new })(target: 'jit');
  return ['tear-offs ${builtFactory(builtId: 5).builtId} ${runner.target}'];
}
