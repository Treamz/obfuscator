extension OnAnything on Object {
  String kindName() => 'generic';
}

class Thing {
  String report() => kindName();
}
