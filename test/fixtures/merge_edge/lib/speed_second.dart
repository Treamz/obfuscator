enum _Speed { _fast, slow }

class Runner {
  String _fast() => 'second';

  String run() => '${_fast()} ${_Speed._fast.name} ${_Speed.values.length}';
}
