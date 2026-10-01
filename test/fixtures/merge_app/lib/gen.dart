part 'gen.g.dart';

class Model {
  Model(this.title);

  final String title;
}

List<String> genReport() => ['gen ${describe(Model('t'))}'];
