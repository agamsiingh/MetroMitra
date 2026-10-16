/// Binary min-heap. Equal elements pop in insertion order, which keeps
/// Dijkstra deterministic regardless of hash or list ordering.
class MinHeap<T> {
  MinHeap(this._compare);

  final int Function(T a, T b) _compare;
  final List<(T, int)> _items = [];
  int _counter = 0;

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  int _cmp((T, int) a, (T, int) b) {
    final c = _compare(a.$1, b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  }

  void add(T value) {
    _items.add((value, _counter++));
    var i = _items.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_cmp(_items[i], _items[p]) >= 0) break;
      final t = _items[i];
      _items[i] = _items[p];
      _items[p] = t;
      i = p;
    }
  }

  T removeFirst() {
    final top = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      for (;;) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _items.length && _cmp(_items[l], _items[m]) < 0) m = l;
        if (r < _items.length && _cmp(_items[r], _items[m]) < 0) m = r;
        if (m == i) break;
        final t = _items[i];
        _items[i] = _items[m];
        _items[m] = t;
        i = m;
      }
    }
    return top.$1;
  }
}
