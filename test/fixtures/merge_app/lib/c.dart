import 'src/helpers.dart' as h;

const _kPad = 1;

enum Mode { fast, slow }

List<String> cReport([int? optional]) {
  var _ = 1;
  var _ = 2;
  Mode mode = .fast;
  final h.HelperModel model = h.HelperModel(h.max(5, 1));
  return ['c $_kPad ${h.helperValue} ${model.amount} ${[?optional, 4]} ${mode.name}'];
}
