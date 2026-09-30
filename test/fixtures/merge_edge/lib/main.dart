import 'coded_impl.dart';
import 'dyn_child.dart';
import 'ext_overrides.dart';
import 'implicit_ext_specific.dart';
import 'interp_math.dart';
import 'interp_values.dart';
import 'json_encode.dart';
import 'json_prefix.dart';
import 'legacy.dart';
import 'prefix_math.dart';
import 'switch_shadow.dart';

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
  ]) {
    print(line);
  }
}
