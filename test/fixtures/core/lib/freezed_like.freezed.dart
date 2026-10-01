part of 'freezed_like.dart';

mixin _$User {
  String get name;
}

class _User implements User {
  const _User({required this.name});

  @override
  final String name;
}
