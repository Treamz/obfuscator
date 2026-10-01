import 'repository.dart';

final repositoryLogs = <String>[];

void _log(String message) => repositoryLogs.add('fake: $message');

class FakeRepository implements Repository {
  @override
  final List<String> history = [];

  @override
  String load(String key) {
    _log('load $key');
    return 'fake-$key';
  }

  @override
  String loadLogged(String key) => load(key);
}
