import 'package:core/alias_ctor.dart';
import 'package:core/api.dart';
import 'package:core/callbacks.dart';
import 'package:core/core_types.dart';
import 'package:core/dynamic_access.dart';
import 'package:core/freezed_like.dart';
import 'package:core/inherited.dart';
import 'package:core/misc.dart';
import 'package:core/overrides.dart';
import 'package:core/patterns.dart';
import 'package:core/platform_report.dart';
import 'package:core/private_one.dart';
import 'package:core/promotion.dart';
import 'package:core/private_two.dart';
import 'package:core/redirect.dart';
import 'package:core/shadow.dart';
import 'package:core/shapes.dart';
import 'package:core/supers.dart';

void main() {
  for (final line in [
    ...aliasReport(),
    ...apiReport(),
    ...callbacksReport(),
    ...coreTypesReport(),
    ...dynamicReport(),
    ...freezedLikeReport(),
    ...inheritedReport(),
    ...miscReport(),
    ...overridesReport(),
    ...patternsReport(),
    ...platformReport(),
    ...privateOneReport(),
    ...promotionReport(),
    ...privateTwoReport(),
    ...redirectReport(),
    ...shadowReport(),
    ...shapesReport(),
    ...supersReport(),
  ]) {
    print(line);
  }
}
