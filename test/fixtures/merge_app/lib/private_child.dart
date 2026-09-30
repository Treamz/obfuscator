import 'private_base.dart';

class PrivateChild extends PrivateBase {
  // Library-private, it doesn't override `PrivateBase._init`.
  String _init() => 'child';

  String own() => _init();
}

extension on String {
  String get _tag => 'child-tag';
}

List<String> privateReport() => ['private ${PrivateChild().setup()} ${PrivateChild().own()} ${baseTag()} ${''._tag}'];
