abstract class Service {
  String _secret() => 'real';

  String greet() => 'hello';
}

String describeService(Service service) {
  final greeting = service.greet();
  try {
    return '$greeting ${service._secret()}';
  } on NoSuchMethodError {
    return '$greeting no-secret';
  }
}
