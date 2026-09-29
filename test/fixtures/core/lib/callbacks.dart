class Button {
  Button(this.onTap(int value));

  final void Function(int) onTap;
}

List<String> callbacksReport() {
  var tapped = 0;
  Button((value) => tapped = value).onTap(5);
  return ['tapped $tapped'];
}
