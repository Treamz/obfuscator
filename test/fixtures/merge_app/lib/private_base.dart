class PrivateBase {
  String _init() => 'base';

  String setup() => _init();
}

extension on String {
  String get _tag => 'base-tag';
}

String baseTag() => ''._tag;
