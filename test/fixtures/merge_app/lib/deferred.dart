import 'src/helpers.dart' deferred as lazy;

Future<String> deferredValue() async {
  await lazy.loadLibrary();
  return 'deferred ${lazy.helperValue}';
}
