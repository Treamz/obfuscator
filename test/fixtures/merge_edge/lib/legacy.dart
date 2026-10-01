// @dart=2.19
class Loud {
  String shout(String s) => s.toUpperCase();
}

class Speaker with Loud {}
