import 'string_ext.dart';

class Member {
  Member(this.name, [this.nickname]);

  final String name;

  final String? nickname;
}

class Profile {
  Profile(this.member);

  final Member? member;
}

String? displayName(Profile? profile) => profile?.member?.name.capitalize();

int? initialsLength(Member? member) => member?.name.initials.length;

String? nicknameOrDash(Member? member) => member?.nickname.orDash();
