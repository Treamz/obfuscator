export 'dart:collection' show LinkedHashSet, HashMap;

// The own declaration shadows the exported one, for the importers of this library.
// ignore: non_constant_identifier_names
String HashMap() => 'own';

List<String> apiExportReport() => ['api ${HashMap()}'];
