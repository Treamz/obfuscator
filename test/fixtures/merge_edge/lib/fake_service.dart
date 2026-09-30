import 'service.dart';

class FakeService implements Service {
  @override
  dynamic noSuchMethod(Invocation invocation) => 'faked';
}
