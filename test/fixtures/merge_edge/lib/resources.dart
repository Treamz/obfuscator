import 'dart:io';
import 'dart:isolate';

Future<String> resourceReport() async {
  final uri = await Isolate.resolvePackageUri(Uri.parse('package:merge_edge/data/config.json'));
  return 'resource ${File.fromUri(uri!).readAsStringSync().trim()}';
}
