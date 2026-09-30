class Wide {
  int _low = 1;

  // The field of `other` is accessed dynamically, the access can't be matched to the declaration.
  int sum(dynamic other) => _low + (other._low as int);
}

List<String> dynamicReport() => ['dynamic ${Wide().sum(Wide())}'];
