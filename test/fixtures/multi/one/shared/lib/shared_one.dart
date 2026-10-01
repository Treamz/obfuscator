export 'dart:collection' show Queue;

class Entity {
  Entity(this.id);

  final int id;

  String get label => 'entity $id';
}
