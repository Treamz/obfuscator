abstract class Shape {
  double get area;
}

class Circle extends Shape {
  Circle(this.area);

  @override
  final double area;
}

class Square implements Shape {
  Square(this.side);

  final double side;

  @override
  double get area => side * side;
}

List<String> shapesReport() => [for (final shape in <Shape>[Circle(2), Square(3)]) 'shape ${shape.area}'];
