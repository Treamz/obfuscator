const publicApi = Object();

class Tag {
  const Tag();
}

@publicApi
class Api {
  Api(this.message);

  final String message;
}

@Tag()
class Tagged {
  Tagged(this.tagValue);

  final int tagValue;
}

class Keep {
  final int keepMe = 1;
}

class Settings {
  String keptField = 'k';
  String otherField = 'o';
}

class Unused {
  int unusedField = 0;
}

List<String> apiReport() => [
  'api ${Api('m').message}',
  'tagged ${Tagged(3).tagValue}',
  'keep ${Keep().keepMe}',
  'settings ${Settings().keptField}${Settings().otherField}',
];
