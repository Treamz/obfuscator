#!/usr/bin/env dart
import '.gen/defaults.dart';
import 'box.dart';
import 'box_impl.dart';
import 'coded_impl.dart';
import 'null_aware/badge.dart';
import 'null_aware/profile.dart';
import 'shared/first.dart';
import 'shared/local.dart';
import 'shared/other.dart';
import 'speed_first.dart';
import 'speed_second.dart';
import 'stubs/config.dart';
import 'stubs/fake_repository.dart';
import 'stubs/fixed_config.dart';
import 'dev_ext.dart';
import 'dev_ext_prefixed.dart';
import 'fake_service.dart';
import 'fixed_holder.dart';
import 'grades/a.dart' as grade_a;
import 'grades/b.dart' as grade_b;
import 'grades/c.dart' as grade_c;
import 'holder.dart';
import 'lazy_loader.dart';
import 'legacy_generics.dart';
import 'pick.dart';
import 'prefix_json.dart';
import 'prefix_math_part.dart';
import 'quiet_ext.dart';
import 'resources.dart';
import 'service.dart';
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
    'part prefix ${encodePair()} ${biggestWithHelper()}',
    pickReport(),
    'grades ${grade_a.Grade.low} ${grade_b.Grade.high} ${grade_c.Grade.mid}',
    'service ${describeService(FakeService())}',
    await lazyReport(),
    'ext ${loudPart()} ${loudPrefixed()} ${quietShout()}',
    'generics ${firstOf<int>([1, 2])} ${LegacyBox<String>('boxed').value} ${biggestOf([3, 9, 4])}',
    await resourceReport(),
    'holder ${Holder(4).doubled} ${FixedHolder().doubled}',
    'null aware ${displayName(Profile(Member('ann lee')))} ${displayName(Profile(null))} ${displayName(null)}',
    'null aware ${initialsLength(Member('ann lee'))} ${initialsLength(null)} ${nicknameOrDash(Member('a'))} ${nicknameOrDash(null)}',
    badge('ok'),
    'repository ${FakeRepository().load('a')} ${FakeRepository().loadLogged('b')} $repositoryLogs',
    'configs ${const <Config>[Config('x'), Config(), fixedConfig].map((config) => config.value).join(' ')}',
    'speed ${Stopwatch2().run()} ${Runner().run()}',
    'shared ${sharedLocal('a')} ${sharedOther('b')} ${sharedFirst('c')}',
    'walker ${Walker().walk([1, 2, 3])} ${current()}',
  ]) {
    print(line);
  }
}
