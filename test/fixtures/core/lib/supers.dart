class BaseButton {
  const BaseButton({required this.label});

  final String label;
}

class PrimaryButton extends BaseButton {
  const PrimaryButton.primary({required super.label});
}

class SizedBase {
  SizedBase(this.size);

  final int size;
}

class SizedChild extends SizedBase {
  SizedChild(int size) : doubled = size * 2, super(size);

  final int doubled;

  // ignore: overridden_fields, annotate_overrides
  final int size = 7;
}

List<String> supersReport() {
  final SizedBase child = SizedChild(3);
  return [
    'button ${const PrimaryButton.primary(label: 'p').label}',
    'sized ${child.size} ${(child as SizedChild).doubled}',
  ];
}
