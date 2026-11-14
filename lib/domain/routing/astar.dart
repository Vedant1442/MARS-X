// MARS-X routing core: A* / Dijkstra on an 8-connected grid, path smoothing, validation.
// Typed arrays + array-based binary heap: no per-node objects, fast enough for ~1M cells.

import 'dart:math' as math;
import 'dart:typed_data';

import 'cost_model.dart';

class SearchResult {
  final List<int> path; // cell indices, start..goal
  final double cost;
  final int expanded; // nodes popped from the open list (for "compare algorithms" mode)
  const SearchResult(this.path, this.cost, this.expanded);
}

const _dx = [1, -1, 0, 0, 1, 1, -1, -1];
const _dy = [0, 0, 1, -1, 1, -1, 1, -1];

/// A* search. Set [dijkstra] to true to disable the heuristic (h = 0).
/// Returns null when no path exists under the profile's limits.
SearchResult? aStar(CostModel m, int start, int goal, {bool dijkstra = false}) {
  final g = m.grid;
  final n = g.cellCount;
  if (m.passable[start] == 0 || m.passable[goal] == 0) return null;

  final gScore = Float64List(n)..fillRange(0, n, double.infinity);
  final parent = Int32List(n)..fillRange(0, n, -1);
  final closed = Uint8List(n);
  final heap = _MinHeap();

  gScore[start] = 0;
  heap.push(dijkstra ? 0.0 : m.heuristic(start, goal), start);
  var expanded = 0;

  while (heap.isNotEmpty) {
    final cur = heap.pop();
    if (closed[cur] == 1) continue; // stale heap entry
    closed[cur] = 1;
    expanded++;
    if (cur == goal) break;

    final cx = g.xOf(cur), cy = g.yOf(cur);
    final gc = gScore[cur];
    for (var k = 0; k < 8; k++) {
      final nx = cx + _dx[k], ny = cy + _dy[k];
      if (!g.inBounds(nx, ny)) continue;
      final nb = g.index(nx, ny);
      if (closed[nb] == 1) continue;
      final c = m.edgeCost(cur, nb);
      if (c == double.infinity) continue;
      final tentative = gc + c;
      if (tentative < gScore[nb]) {
        gScore[nb] = tentative;
        parent[nb] = cur;
        heap.push(tentative + (dijkstra ? 0.0 : m.heuristic(nb, goal)), nb);
      }
    }
  }

  if (gScore[goal] == double.infinity) return null;
  final path = <int>[];
  for (var c = goal; c != -1; c = parent[c]) {
    path.add(c);
  }
  return SearchResult(path.reversed.toList(), gScore[goal], expanded);
}

/// Total cost of a path under a model (infinity if any step is illegal).
double pathCost(CostModel m, List<int> path) {
  var c = 0.0;
  for (var i = 1; i < path.length; i++) {
    c += m.edgeCost(path[i - 1], path[i]);
  }
  return c;
}

/// 8-connected Bresenham line between two cells (inclusive).
List<int> gridLine(CostModel m, int a, int b) {
  final g = m.grid;
  var x0 = g.xOf(a), y0 = g.yOf(a);
  final x1 = g.xOf(b), y1 = g.yOf(b);
  final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
  final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  final out = <int>[g.index(x0, y0)];
  while (x0 != x1 || y0 != y1) {
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
    out.add(g.index(x0, y0));
  }
  return out;
}

/// "String pulling": replace staircase sections with straight grid lines when the
/// straight line is legal and costs no more than [tolerance] above the original section.
/// Output is still a valid 8-connected grid path, so validation stays exact.
List<int> smoothPath(CostModel m, List<int> path,
    {double tolerance = 0.02, int maxLookahead = 60}) {
  if (path.length < 3) return List.of(path);
  final prefix = Float64List(path.length);
  for (var i = 1; i < path.length; i++) {
    prefix[i] = prefix[i - 1] + m.edgeCost(path[i - 1], path[i]);
  }
  final out = <int>[path.first];
  var i = 0;
  while (i < path.length - 1) {
    var advanced = false;
    for (var j = math.min(path.length - 1, i + maxLookahead); j >= i + 2; j--) {
      final line = gridLine(m, path[i], path[j]);
      final lc = pathCost(m, line);
      if (lc.isFinite && lc <= (prefix[j] - prefix[i]) * (1 + tolerance)) {
        out.addAll(line.skip(1));
        i = j;
        advanced = true;
        break;
      }
    }
    if (!advanced) {
      out.add(path[i + 1]);
      i++;
    }
  }
  return out;
}

/// Checks the invariants every route must satisfy. Returns a list of problems (empty = valid).
List<String> validatePath(CostModel m, List<int> path, int start, int goal) {
  final problems = <String>[];
  if (path.isEmpty) return ['empty path'];
  if (path.first != start) problems.add('does not start at start');
  if (path.last != goal) problems.add('does not end at goal');
  for (final c in path) {
    if (m.passable[c] == 0) {
      problems.add('crosses an excluded cell ($c)');
      break;
    }
  }
  for (var i = 1; i < path.length; i++) {
    if (m.edgeCost(path[i - 1], path[i]) == double.infinity) {
      problems.add('illegal or non-adjacent step at $i');
      break;
    }
  }
  return problems;
}

/// Nearest passable cell to [cell] within [radiusM] (BFS ring search). -1 if none.
int snapToPassable(CostModel m, int cell, double radiusM) {
  if (cell >= 0 && m.passable[cell] == 1) return cell;
  if (cell < 0) return -1;
  final g = m.grid;
  final r = (radiusM / g.cellSize).ceil();
  final cx = g.xOf(cell), cy = g.yOf(cell);
  var best = -1;
  var bestD = double.infinity;
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if (!g.inBounds(x, y)) continue;
      final i = g.index(x, y);
      if (m.passable[i] == 0) continue;
      final d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble();
      if (d < bestD && math.sqrt(d) * g.cellSize <= radiusM) {
        bestD = d;
        best = i;
      }
    }
  }
  return best;
}

class _MinHeap {
  Float64List _k = Float64List(4096);
  Int32List _v = Int32List(4096);
  int _size = 0;

  bool get isNotEmpty => _size > 0;

  void push(double key, int value) {
    if (_size == _k.length) {
      _k = Float64List(_size * 2)..setRange(0, _size, _k);
      _v = Int32List(_size * 2)..setRange(0, _size, _v);
    }
    var i = _size++;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_k[p] <= key) break;
      _k[i] = _k[p];
      _v[i] = _v[p];
      i = p;
    }
    _k[i] = key;
    _v[i] = value;
  }

  int pop() {
    final top = _v[0];
    _size--;
    if (_size > 0) {
      final key = _k[_size], val = _v[_size];
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        if (l >= _size) break;
        final r = l + 1;
        final c = (r < _size && _k[r] < _k[l]) ? r : l;
        if (_k[c] >= key) break;
        _k[i] = _k[c];
        _v[i] = _v[c];
        i = c;
      }
      _k[i] = key;
      _v[i] = val;
    }
    return top;
  }
}
