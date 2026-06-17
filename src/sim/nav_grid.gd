class_name NavGrid
extends RefCounted
## Deterministic grid pathfinding over the arena's obstacles — the routing behind click-to-move
## and the bots' approach, so a unit threads the jungle walls and rounds the towers instead of
## walking into them.
##
## A coarse occupancy grid is baked once from MapData.obstacles() (the map is static), a cell
## marked blocked when a unit centred there would overlap an obstacle. `find_path` runs an
## 8-connected A* with integer costs and an index tie-break, then a line-of-sight string-pull, so
## the same call yields a byte-identical path on every machine. Pure GDScript — no engine, render,
## or NavigationServer coupling — so it lives in the sim layer beside the rest of the deterministic
## core: a bot's route is part of the replayable simulation, and a client predicts its own with the
## same math. Built around MapData and SimCore.UNIT_RADIUS, the same footprint the collision uses,
## so a routed path and the movement resolve agree.

## Grid cell size in world units. Fine enough to thread the wall gaps (~490 between the rocks that
## bound a gank opening), coarse enough that a full-map search stays cheap.
const CELL := 128.0

## Integer step costs (orthogonal / diagonal ≈ 1 : √2) — integers keep A* fully deterministic.
const COST_ORTHO := 10
const COST_DIAG := 14

## A stand-in for an unreached g-score; larger than any real path cost on this grid.
const INF_COST := 1 << 30

## The eight grid neighbours as (dcol, drow, step-cost) — precomputed so the A* inner loop allocates
## nothing per cell.
const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(-1, -1, COST_DIAG),
	Vector3i(0, -1, COST_ORTHO),
	Vector3i(1, -1, COST_DIAG),
	Vector3i(-1, 0, COST_ORTHO),
	Vector3i(1, 0, COST_ORTHO),
	Vector3i(-1, 1, COST_DIAG),
	Vector3i(0, 1, COST_ORTHO),
	Vector3i(1, 1, COST_DIAG),
]

static var _shared: NavGrid = null

var _cols: int = 0
var _rows: int = 0
var _origin: Vector2 = Vector2.ZERO
var _blocked: PackedByteArray = PackedByteArray()

# Scratch reused across an A* run, sized to the grid in `_init`.
var _g: PackedInt32Array = PackedInt32Array()
var _came: PackedInt32Array = PackedInt32Array()
var _closed: PackedByteArray = PackedByteArray()
var _heap_f: PackedInt32Array = PackedInt32Array()
var _heap_i: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var bounds := MapData.BOUNDS
	_origin = bounds.position
	_cols = int(ceil(bounds.size.x / CELL))
	_rows = int(ceil(bounds.size.y / CELL))
	_bake()


## The lazily-baked shared grid. The layout is a pure function of MapData's static geometry, so one
## bake serves the whole process and stays deterministic.
static func shared() -> NavGrid:
	if _shared == null:
		_shared = NavGrid.new()
	return _shared


## Marks every cell a unit could not stand in (its centre, inflated by the body radius, overlaps an
## obstacle). Stamps each obstacle's bounding box rather than testing every cell against every
## obstacle, so the bake is a few thousand checks instead of millions. The grid uses the same
## SimCore.UNIT_RADIUS the collision does, so a free cell is a spot the resolve also accepts.
func _bake() -> void:
	var total := _cols * _rows
	_blocked.resize(total)
	_blocked.fill(0)
	for o in MapData.obstacles():
		var center: Vector2 = o["center"]
		var reach: float = o["radius"] + SimCore.UNIT_RADIUS
		var min_col := clampi(int((center.x - reach - _origin.x) / CELL), 0, _cols - 1)
		var max_col := clampi(int((center.x + reach - _origin.x) / CELL), 0, _cols - 1)
		var min_row := clampi(int((center.y - reach - _origin.y) / CELL), 0, _rows - 1)
		var max_row := clampi(int((center.y + reach - _origin.y) / CELL), 0, _rows - 1)
		for row in range(min_row, max_row + 1):
			for col in range(min_col, max_col + 1):
				var i := row * _cols + col
				if _blocked[i] == 0 and _cell_center(i).distance_to(center) < reach:
					_blocked[i] = 1


## A path of world waypoints from `from` to `to` that avoids the obstacles, or an empty array when
## the goal is unreachable (the caller then falls back to a direct move). The returned points lead
## from the first turn to the destination — the hero, already at `from`, walks toward waypoint 0.
## A clear straight line short-circuits to the single point `to`; otherwise A* routes the grid and a
## line-of-sight pass pulls the staircase taut. If `to` sits in an obstacle the route ends at the
## nearest free cell, but a clear final leg still lands on the real `to`.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if segment_clear(from, to):
		var direct := PackedVector2Array()
		direct.append(to)
		return direct
	var start_i := _nearest_free(_cell_of(from))
	var goal_i := _nearest_free(_cell_of(to))
	if start_i < 0 or goal_i < 0:
		return PackedVector2Array()
	if not _astar(start_i, goal_i):
		return PackedVector2Array()
	var cells := _reconstruct(start_i, goal_i)
	# Turn the cell chain (minus the start cell the unit already occupies) into world points,
	# landing the last leg on the real `to` when its cell was free rather than the cell centre.
	var raw := PackedVector2Array()
	for k in range(1, cells.size()):
		raw.append(_cell_center(cells[k]))
	if raw.size() > 0 and _cell_of(to) == goal_i:
		raw[raw.size() - 1] = to
	return _smooth(from, raw)


# --- A* ------------------------------------------------------------------------------------

## Runs the search from `start_i` to `goal_i`, filling `_came`. Returns whether the goal was
## reached. Lazy heap with a `_closed` set: the first time a cell is popped it has its lowest f
## (the octile heuristic is consistent), so it is finalised once; later stale heap entries are
## skipped. Costs and the heuristic are integers and the heap breaks ties by cell index, so the
## search is deterministic.
func _astar(start_i: int, goal_i: int) -> bool:
	var total := _cols * _rows
	_g = PackedInt32Array()
	_g.resize(total)
	_g.fill(INF_COST)
	_came = PackedInt32Array()
	_came.resize(total)
	_came.fill(-1)
	_closed = PackedByteArray()
	_closed.resize(total)
	_heap_f = PackedInt32Array()
	_heap_i = PackedInt32Array()
	_g[start_i] = 0
	_heap_push(_heuristic(start_i, goal_i), start_i)
	while _heap_i.size() > 0:
		var cur := _heap_pop()
		if cur == goal_i:
			return true
		if _closed[cur] == 1:
			continue
		_closed[cur] = 1
		var col := cur % _cols
		var row := cur / _cols
		for nb in NEIGHBOURS:
			var nc := col + nb.x
			var nr := row + nb.y
			if nc < 0 or nc >= _cols or nr < 0 or nr >= _rows:
				continue
			var n := nr * _cols + nc
			if _blocked[n] == 1 or _closed[n] == 1:
				continue
			if nb.x != 0 and nb.y != 0:
				# No corner-cutting: a diagonal needs both flanking orthogonals open, so a unit
				# never squeezes through a one-cell diagonal slit in a wall.
				if _blocked[row * _cols + nc] == 1 or _blocked[nr * _cols + col] == 1:
					continue
			var tentative := _g[cur] + nb.z
			if tentative < _g[n]:
				_g[n] = tentative
				_came[n] = cur
				_heap_push(tentative + _heuristic(n, goal_i), n)
	return false


## The octile heuristic between two cells, in the same integer units as the step costs and
## admissible/consistent for 8-connected movement — `10·(dx+dy) − 6·min(dx,dy)`.
func _heuristic(a: int, b: int) -> int:
	var dx: int = absi(a % _cols - b % _cols)
	var dy: int = absi(a / _cols - b / _cols)
	return COST_ORTHO * (dx + dy) - (2 * COST_ORTHO - COST_DIAG) * mini(dx, dy)


## Walks `_came` back from the goal to the start, returning the cell chain start→goal.
func _reconstruct(start_i: int, goal_i: int) -> PackedInt32Array:
	var rev := PackedInt32Array()
	var cur := goal_i
	while cur != -1:
		rev.append(cur)
		if cur == start_i:
			break
		cur = _came[cur]
	var out := PackedInt32Array()
	for k in range(rev.size() - 1, -1, -1):
		out.append(rev[k])
	return out


# --- min-heap (f, index) -------------------------------------------------------------------
# A binary min-heap ordered by f-score, breaking ties by the lower cell index so the search is
# deterministic. Kept as two parallel packed arrays to avoid per-entry allocation.

func _heap_push(f: int, idx: int) -> void:
	_heap_f.append(f)
	_heap_i.append(idx)
	var c := _heap_f.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if _heap_less(c, p):
			_heap_swap(c, p)
			c = p
		else:
			break


func _heap_pop() -> int:
	var top := _heap_i[0]
	var last := _heap_f.size() - 1
	_heap_f[0] = _heap_f[last]
	_heap_i[0] = _heap_i[last]
	_heap_f.remove_at(last)
	_heap_i.remove_at(last)
	var n := _heap_f.size()
	var c := 0
	while true:
		var l := 2 * c + 1
		var r := 2 * c + 2
		var smallest := c
		if l < n and _heap_less(l, smallest):
			smallest = l
		if r < n and _heap_less(r, smallest):
			smallest = r
		if smallest == c:
			break
		_heap_swap(c, smallest)
		c = smallest
	return top


## Whether heap entry `a` orders before `b`: lower f first, then the lower cell index — the
## deterministic tie-break that pins one path among equal-cost routes.
func _heap_less(a: int, b: int) -> bool:
	if _heap_f[a] != _heap_f[b]:
		return _heap_f[a] < _heap_f[b]
	return _heap_i[a] < _heap_i[b]


func _heap_swap(a: int, b: int) -> void:
	var tf := _heap_f[a]
	_heap_f[a] = _heap_f[b]
	_heap_f[b] = tf
	var ti := _heap_i[a]
	_heap_i[a] = _heap_i[b]
	_heap_i[b] = ti


# --- geometry helpers ----------------------------------------------------------------------

## The cell index containing a world point, clamped into the grid so an out-of-bounds point maps to
## the nearest edge cell.
func _cell_of(p: Vector2) -> int:
	var col := clampi(int((p.x - _origin.x) / CELL), 0, _cols - 1)
	var row := clampi(int((p.y - _origin.y) / CELL), 0, _rows - 1)
	return row * _cols + col


func _cell_center(i: int) -> Vector2:
	var col := i % _cols
	var row := i / _cols
	return _origin + Vector2((float(col) + 0.5) * CELL, (float(row) + 0.5) * CELL)


## The nearest free cell to `i`, searched in rings of growing Chebyshev radius (deterministic
## row-then-column order within a ring). Returns `i` itself when already free, or -1 if the whole
## grid is blocked (it never is).
func _nearest_free(i: int) -> int:
	if _blocked[i] == 0:
		return i
	var col := i % _cols
	var row := i / _cols
	var max_r := maxi(_cols, _rows)
	for r in range(1, max_r + 1):
		for dr in range(-r, r + 1):
			for dc in range(-r, r + 1):
				if absi(dr) != r and absi(dc) != r:
					continue  # only the ring's perimeter
				var nc := col + dc
				var nr := row + dr
				if nc < 0 or nc >= _cols or nr < 0 or nr >= _rows:
					continue
				if _blocked[nr * _cols + nc] == 0:
					return nr * _cols + nc
	return -1


## A line-of-sight string-pull over the raw waypoints: from the unit's position, greedily keep the
## farthest point still reachable in a clear straight line, so the cell-stepped path is pulled into
## a few long legs instead of a staircase.
func _smooth(from: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < pts.size():
		var j := i
		var k := i
		while k < pts.size() and segment_clear(anchor, pts[k]):
			j = k
			k += 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


## Whether the straight segment a→b stays on free cells, sampled at half-cell steps (obstacles span
## several cells, so nothing slips between samples). Reads the baked grid — an O(1) lookup per
## sample instead of testing every obstacle — so it is cheap enough to call each tick.
func segment_clear(a: Vector2, b: Vector2) -> bool:
	var delta := b - a
	var steps := maxi(1, int(ceil(delta.length() / (CELL * 0.5))))
	for s in steps + 1:
		if _blocked[_cell_of(a + delta * (float(s) / float(steps)))] == 1:
			return false
	return true
