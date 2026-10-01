class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;
}

int sum(Object object) => switch (object) {
  Point(x: var px, :final y) => px + y,
  _ => 0,
};

String describe(Point point) {
  final Point(:x, y: py) = point;
  return '$x/$py';
}

List<String> patternsReport() => ['sum ${sum(const Point(2, 3))}', 'describe ${describe(const Point(4, 5))}'];
