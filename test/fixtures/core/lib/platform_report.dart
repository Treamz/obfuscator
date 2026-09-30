import 'package:core/platform.dart';

// The analyzer resolves the default alternative, while the VM uses the `dart.library.io` one.
List<String> platformReport() => ['platform ${PlatformInfo.label} ${PlatformInfo().code}'];
