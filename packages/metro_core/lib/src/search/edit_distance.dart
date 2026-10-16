/// Restricted Damerau-Levenshtein (optimal string alignment) distance over
/// Unicode code points, bounded: returns null as soon as the distance must
/// exceed [max]. Insert, delete, substitute and adjacent transposition each
/// cost 1.
int? boundedEditDistance(String a, String b, int max) {
  final x = a.runes.toList(growable: false);
  final y = b.runes.toList(growable: false);
  if ((x.length - y.length).abs() > max) return null;
  if (x.isEmpty) return y.length <= max ? y.length : null;
  if (y.isEmpty) return x.length <= max ? x.length : null;

  var prev2 = List<int>.filled(y.length + 1, 0);
  var prev = List<int>.generate(y.length + 1, (j) => j);
  var cur = List<int>.filled(y.length + 1, 0);
  for (var i = 1; i <= x.length; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      var v = prev[j - 1] + cost;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (i > 1 &&
          j > 1 &&
          x[i - 1] == y[j - 2] &&
          x[i - 2] == y[j - 1] &&
          prev2[j - 2] + 1 < v) {
        v = prev2[j - 2] + 1;
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return null;
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  final d = prev[y.length];
  return d <= max ? d : null;
}
