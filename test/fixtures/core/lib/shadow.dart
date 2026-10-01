class Counter {
  int count = 0;

  int run() {
    var count = 10;
    count++;
    ++count;
    count += 1;
    this.count += 100;
    return count;
  }
}

class Parent {
  int hits = 0;
}

class Kid extends Parent {
  void hit() {
    hits++;
    ++hits;
    hits += 2;
    this.hits *= 2;
  }
}

List<String> shadowReport() {
  final counter = Counter();
  final result = counter.run();
  final kid = Kid()..hit();
  kid.hits--;
  return ['counter $result ${counter.count}', 'kid ${kid.hits}'];
}
