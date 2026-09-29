part 'route.gr.dart';

class RoutePage {
  const RoutePage();
}

class Args {
  const Args(this.id);

  final int id;
}

@RoutePage()
class DetailsPage {
  const DetailsPage({required this.id});

  final int id;
}

List<String> routeReport() => ['route ${buildDetails(const Args(8)).id}'];
