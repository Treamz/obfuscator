import 'holder.dart';

class HolderBase {}

mixin Fixed {
  int get doubled => -1;
}

class FixedHolder = HolderBase with Fixed implements Holder;
