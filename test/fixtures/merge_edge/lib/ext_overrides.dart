import 'dart:async' as async_prefix;

import 'ext_first.dart' as first;
import 'ext_second.dart' as second;

Future<List<String>> extOverridesReport() async {
  final failed = Future<int>.error('ignored');
  async_prefix.FutureExtensions(failed).ignore();
  return ['overrides ${first.Shout('hi').shout()} ${first.fromFirst(1)} ${second.fromSecond(2)}'];
}
