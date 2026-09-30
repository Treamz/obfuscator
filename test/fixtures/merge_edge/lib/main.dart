#!/usr/bin/env dart
import '.gen/defaults.dart';
import 'box.dart';
import 'box_impl.dart';
import 'coded_impl.dart';
import 'counting.dart';
import 'counting_docs.dart';
import 'current.dart';
import 'dev_usage.dart';
import 'dyn_child.dart';
import 'feature_a/status.dart' as status_a;
import 'feature_b/status.dart' as status_b;
import 'ext_overrides.dart';
import 'implicit_ext_specific.dart';
import 'interp_math.dart';
import 'interp_values.dart';
import 'json_encode.dart';
import 'json_prefix.dart';
import 'legacy.dart';
import 'prefix_math.dart';
import 'switch_shadow.dart';
import 'walker.dart';
import 'wildcards.dart';

Future<void> main() async {
  for (final line in [
    ...switchReport(),
    ...await extOverridesReport(),
    'prefix ${biggest(1, 2)}',
    'interp ${piFromMath()} ${piFromValues()}',
    'json ${encodeJson()} ${jsonMax()}',
    ...codedReport(),
    ...implicitReport(),
    'legacy ${Speaker().shout('hey')} ${switch (1 as Object) { int() => 'int', _ => 'other' }}',
    ...dynamicReport(),
    'status ${status_a.statusA()} ${status_b.statusB()}',
    'wildcards ${twice(4)} ${wildcardName()}',
    'hidden ${defaultConfig().port}',
    'counting ${CountA().count()} ${CountB().count()}',
    'box ${Box(1).value} ${const ConstBox().value} ${EnumBox.only.value}',
    'dev ${devUsage()}',
    'walker ${Walker().walk([1, 2, 3])} ${current()}',
  ]) {
    print(line);
  }
}
