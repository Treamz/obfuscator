import 'package:shared_one/shared_one.dart';

class User extends Entity {
  User(super.id, this.name);

  final String name;

  // ignore: overridden_fields, annotate_overrides
  final int id = 100;
}

void main() {
  final Entity entity = User(1, 'bob');
  print('${entity.id} ${entity.label} ${(entity as User).name}');
}
