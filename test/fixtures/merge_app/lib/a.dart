import 'package:localdep/localdep.dart';
import 'dart:math'; // for max

List<String> aReport() => ['a ${max(1, 2)} ${Widget().kind}'];
