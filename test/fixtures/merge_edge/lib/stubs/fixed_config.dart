import 'config.dart';

mixin FixedValue {
  String get value => 'fixed';
}

class FixedConfig = Object with FixedValue implements Config;

const fixedConfig = FixedConfig();
