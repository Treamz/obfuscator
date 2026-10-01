abstract class Repository {
  final List<String> history = [];

  String load(String key);

  void _log(String message) => history.add(message);

  String loadLogged(String key) {
    _log('load $key');
    return load(key);
  }
}
