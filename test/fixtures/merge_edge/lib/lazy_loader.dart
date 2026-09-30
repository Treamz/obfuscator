import 'heavy.dart' deferred as heavy;

Future<String> lazyReport() async {
  final Future<void> Function() loader = heavy.loadLibrary;
  await loader();
  return 'lazy ${heavy.heavyCompute()}';
}
