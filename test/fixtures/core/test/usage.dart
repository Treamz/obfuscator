import 'package:core/shapes.dart';
import 'package:core/src/models.dart';

// References from outside of `lib` must be updated as well.
double usage() => Circle(1).area + Box<int>(2).content;
