part 'freezed_like.freezed.dart';

const freezed = Object();

@freezed
abstract class User with _$User {
  const factory User({required String name}) = _User;
}

List<String> freezedLikeReport() => ['user ${const User(name: 'ann').name}'];
