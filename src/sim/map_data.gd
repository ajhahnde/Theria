class_name MapData
extends RefCounted
## Static geometry for the 3v3 arena.
##
## The map is axially symmetric across the TL–BR diagonal — the line y = x: team 1's
## geometry is team 0's reflected across that axis, (x, y) → (y, x), which swaps the two
## bases so neither side has a positional edge. The simulation reads this layer as pure
## data — bounds, the team bases, the lane corridors, the river, and the neutral jungle
## camps — with no engine or render coupling, so bots, tests, and (later) the netcode share
## one source of truth.

## Playable area, in world units, centred on the origin. Sized to about 65% of a 5v5 map's
## side length — a tighter arena for 3v3.
const BOUNDS := Rect2(-4800.0, -4800.0, 9600.0, 9600.0)

## The nexus position for each team, indexed by team id. The nexus is the win
## condition (destroyed to end the match) and the inner anchor both lane
## corridors converge on at a base. Axially symmetric: index 1 is index 0 mirrored
## across the y = x axis.
const NEXUS_POSITIONS: Array[Vector2] = [
	Vector2(-3840.0, 3840.0),
	Vector2(3840.0, -3840.0),
]

## How far in front of the nexus a team's heroes spawn — a fountain pulled toward
## the map centre so a hero starts at its base without sitting on the nexus.
const FOUNTAIN_PULLBACK := 720.0

## Lateral gap between squadmates fanned across a base fountain, so a full team
## spawns side by side instead of stacked on one point.
const SQUAD_SPACING := 150.0

## Top corridor: out of team 0's base, bulging up the left side, into team 1's base. It is its
## own reflection across the y = x axis (its midpoint sits on the axis), so it is team-fair.
const LANE_TOP: Array[Vector2] = [
	Vector2(-3840.0, 3840.0),
	Vector2(-2640.0, -240.0),
	Vector2(-2160.0, -1440.0),
	Vector2(-1440.0, -2160.0),
	Vector2(-240.0, -2640.0),
	Vector2(3840.0, -3840.0),
]

## Bottom corridor: out of team 0's base, bulging down the right side, into team 1's base. Like
## the top corridor it is its own reflection across the y = x axis, so the two teams meet it
## the same way.
const LANE_BOTTOM: Array[Vector2] = [
	Vector2(-3840.0, 3840.0),
	Vector2(1200.0, 3720.0),
	Vector2(2280.0, 3480.0),
	Vector2(3000.0, 3000.0),
	Vector2(3480.0, 2280.0),
	Vector2(3720.0, 1200.0),
	Vector2(3840.0, -3840.0),
]

## The lane corridors, each a polyline stored from team 0's nexus to team 1's nexus. Both teams
## push both corridors in opposite directions; `lane_path` orients a corridor for a given team's
## travel. Each corridor is its own reflection across the y = x axis, so walking it forward
## (team 0) and reversed (team 1) are mirror experiences. v0.1 is two lanes plus the jungle —
## there is no mid.
const LANES: Array[Array] = [LANE_TOP, LANE_BOTTOM]

## Neutral jungle camp positions in the open ground between the lanes. Closed under the axis
## mirror (every off-axis camp has a partner across y = x; a camp on the axis is its own), so the
## neutral layer stays team-fair: each team reaches the same camps the same way.
const JUNGLE_CAMPS: Array[Vector2] = [
	Vector2(1080.0, 1080.0),
	Vector2(150.0, 2450.0),
	Vector2(-3360.0, -3360.0),
	Vector2(2450.0, 150.0),
	Vector2(1550.0, -1700.0),
	Vector2(-1700.0, 1550.0),
]

## The river: a single watercourse that meanders across the middle of the map, its apex sitting
## on the y = x axis. Stored as a polyline; reflecting it across the axis and reversing maps it
## onto itself, so it divides the map evenly and neither team has more water in its half. Any
## barrier rule that makes the banks block movement is a later step; for now this is just the
## geometry the map is drawn from.
const RIVER: Array[Vector2] = [
	Vector2(720.0, -4800.0),
	Vector2(-200.0, -3900.0),
	Vector2(-550.0, -3550.0),
	Vector2(-750.0, -3200.0),
	Vector2(-850.0, -2800.0),
	Vector2(-800.0, -2400.0),
	Vector2(-550.0, -2100.0),
	Vector2(-300.0, -1800.0),
	Vector2(-200.0, -1500.0),
	Vector2(-200.0, -1100.0),
	Vector2(-300.0, -750.0),
	Vector2(-500.0, -500.0),
	Vector2(-750.0, -300.0),
	Vector2(-1100.0, -200.0),
	Vector2(-1500.0, -200.0),
	Vector2(-1800.0, -300.0),
	Vector2(-2100.0, -550.0),
	Vector2(-2400.0, -800.0),
	Vector2(-2800.0, -850.0),
	Vector2(-3200.0, -750.0),
	Vector2(-3550.0, -550.0),
	Vector2(-3900.0, -200.0),
	Vector2(-4800.0, 720.0),
]

## Every defensive tower slot on the map, as one axially-symmetric set (each off-axis slot has a
## partner across y = x). Per team: two towers ringing the nexus and two forward towers down the
## lanes — four towers a side. `tower_positions` hands a team the slots on its own side of the
## axis, so the two teams field mirror-image defences without either holding an extra tower.
## (The two forward slots are where a future "ford" river-crossing could replace a tower — that
## idea is deferred; for now they are plain towers.)
const TOWER_SLOTS: Array[Vector2] = [
	Vector2(2520.0, -3480.0),
	Vector2(-3480.0, 2520.0),
	Vector2(-2520.0, 3840.0),
	Vector2(3840.0, -2520.0),
	Vector2(-2640.0, -240.0),
	Vector2(-240.0, -2640.0),
	Vector2(840.0, 3720.0),
	Vector2(3720.0, 840.0),
]

# === Collision obstacles ===================================================================
## The solid bodies a moving unit cannot enter and a path routes around: the structures and the
## jungle rock walls. Every obstacle is a circle ({center, radius}); a wall is a chain of
## overlapping circles. The river and the fine cosmetic scatter stay walkable. Derived purely
## from the geometry above (lanes, river, camps, towers, nexuses) and closed under the y = x
## mirror, so collision is team-fair and shares one source of truth with the sim, the bots, the
## nav grid, the tests, and the decor that draws these same rocks. A unit's body radius is owned
## by the sim (SimCore.UNIT_RADIUS); the radii here are the bare obstacle footprints.

## A tower's and the nexus's solid footprint. A forward tower sits on a lane waypoint, so heroes
## route around it while lane creeps (which never collide) still file past — see `obstacles`.
const TOWER_RADIUS := 200.0
const NEXUS_RADIUS := 320.0

## Jungle rock walls: a wall of blocker rocks runs each side of every lane, set back
## LANE_WALL_OFFSET past the path centre, a rock every WALL_STEP (radius WALL_RADIUS, sized so a
## run of them overlaps into a continuous wall even inflated by a unit's body), broken by a
## WALL_GAP_SPAN opening every WALL_GAP_PERIOD — the gank gaps a unit threads. No rock lands
## within WALL_RIVER_CLEAR of the river (the lane fords stay open) or WALL_STRUCT_CLEAR of a
## structure (a tower keeps its own clearance). These mirror the decor that draws them.
const WALL_RADIUS := 95.0
const LANE_WALL_OFFSET := 435.0  # LANE half-width (115) + a 320 setback
const WALL_STEP := 150.0
const WALL_GAP_PERIOD := 1500.0
const WALL_GAP_SPAN := 340.0
const WALL_RIVER_CLEAR := 300.0
const WALL_STRUCT_CLEAR := 360.0
const WALL_SPAWN_CLEAR := 700.0  # no wall rock near a base fountain — the team spawns free

## A neutral camp's rock pocket: a ring of blocker rocks CAMP_POCKET_RADIUS out, left open over
## the CAMP_POCKET_GAP arc facing the map centre so the camp has one entrance. Each ring point is
## paired with its y = x mirror, so the pockets stay team-fair like the camps they wall.
const CAMP_POCKET_RADIUS := 360.0
const CAMP_POCKET_POINTS := 12
const CAMP_POCKET_GAP := 0.5  # cos-threshold of the entrance arc toward the centre
const CAMP_FEATURE_CLEAR := 200.0  # no pocket rock on a lane or in the river

## Lazily-built cache of the obstacle circles — the map is static, so this is baked once and
## reused by the per-tick collision, the nav grid, and the tests.
static var _obstacles: Array = []


## Reflection across the diagonal axis y = x — the map's mirror. An involution (its own inverse)
## that swaps the two bases, so team 1's geometry is team 0's mirrored.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(p.y, p.x)


## A team's hero spawn: its base fountain, set just in front of the nexus toward
## the map centre. Derived from `NEXUS_POSITIONS`, so the two teams' spawns mirror
## across the y = x axis like the rest of the map.
static func spawn_for_team(team: int) -> Vector2:
	var nexus := nexus_for_team(team)
	return nexus - nexus.normalized() * FOUNTAIN_PULLBACK


static func nexus_for_team(team: int) -> Vector2:
	return NEXUS_POSITIONS[team % NEXUS_POSITIONS.size()]


## A squadmate's spawn within its team's roster of `count`, fanned laterally across the base
## fountain so the team starts side by side rather than stacked. `index` runs 0..count-1; the fan
## is centred on the fountain and laid out along the axis perpendicular to the base→centre
## direction. Team 1's seats are team 0's mirrored across y = x, so neither side has an edge.
static func squad_spawn(team: int, index: int, count: int) -> Vector2:
	var seat := _squad_seat_team0(index, count)
	return seat if team % 2 == 0 else mirror(seat)


## Team 0's squad seat for `index` of `count`, the bare geometry the mirror is taken from.
static func _squad_seat_team0(index: int, count: int) -> Vector2:
	var fountain := spawn_for_team(0)
	if count <= 1:
		return fountain
	var inward := -nexus_for_team(0).normalized()  # base toward the map centre
	var lateral := Vector2(-inward.y, inward.x)  # perpendicular to the inward axis
	var offset := float(index) - float(count - 1) * 0.5
	return clamp_to_bounds(fountain + lateral * (offset * SQUAD_SPACING))


## The tower slots for `team`: the stored slots on team 0's side of the y = x axis, handed back
## as-is for team 0 and mirrored for team 1, so the two teams' defences are reflections of each
## other. Returns a fresh copy so callers cannot mutate the stored geometry.
static func tower_positions(team: int) -> PackedVector2Array:
	return _team_side(TOWER_SLOTS, team)


## The members of an axially-symmetric point set that fall on team 0's side of the y = x axis
## (where y > x), handed back as-is for team 0 and mirrored for team 1. A point on the axis
## itself belongs to neither side and is dropped — these are per-team defences, not neutral.
static func _team_side(points: Array[Vector2], team: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if p.y > p.x:  # team 0's side of the diagonal
			out.append(p if team % 2 == 0 else mirror(p))
	return out


static func lane_count() -> int:
	return LANES.size()


## A lane corridor's waypoints oriented for `team`'s travel: team 0 walks the
## stored order (its nexus first), team 1 walks it reversed (its nexus first).
## Returns a fresh copy so callers cannot mutate the stored geometry.
static func lane_path(lane: int, team: int) -> PackedVector2Array:
	var path := PackedVector2Array(LANES[lane])
	if team % 2 == 1:
		path.reverse()
	return path


## The river polyline, as a fresh copy so callers cannot mutate the stored course.
static func river_polyline() -> PackedVector2Array:
	return PackedVector2Array(RIVER)


static func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, BOUNDS.position.x, BOUNDS.end.x),
		clampf(pos.y, BOUNDS.position.y, BOUNDS.end.y),
	)


## The solid obstacle circles (each `{center: Vector2, radius: float}`): every team's towers and
## nexus, plus the jungle rock walls and camp pockets. Baked once and cached — the map is static.
## Closed under the y = x mirror, so the set is team-fair. Callers must treat it as read-only.
static func obstacles() -> Array:
	if _obstacles.is_empty():
		_obstacles = _build_obstacles()
	return _obstacles


static func _build_obstacles() -> Array:
	var out: Array = []
	for team in NEXUS_POSITIONS.size():
		for slot in tower_positions(team):
			out.append({"center": slot, "radius": TOWER_RADIUS})
		out.append({"center": nexus_for_team(team), "radius": NEXUS_RADIUS})
	for p in jungle_wall_points():
		out.append({"center": p, "radius": WALL_RADIUS})
	return out


## The rock centres of the jungle walls and camp pockets — the blocker layout, shared by the sim
## (wrapped into WALL_RADIUS circles in `obstacles`) and the decor (which draws a boulder on each).
## Generated on team 0's side of the y = x axis and mirrored, so the layout is exactly symmetric.
static func jungle_wall_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for lane in LANES:
		_lane_wall_points(pts, lane, 1.0)
		_lane_wall_points(pts, lane, -1.0)
	for camp in JUNGLE_CAMPS:
		if camp.y < camp.x:
			continue  # team 1's side — the mirror below fills it
		_camp_pocket_points(pts, camp)
	return pts


## Lays a wall of blocker points down one side (`sign`) of a lane corridor: stepping along each
## segment, pushed out LANE_WALL_OFFSET along the segment normal, skipping the gank gaps, the
## river crossings, and structure clearances. Each kept point (on team 0's half) is paired with
## its mirror, so the wall is symmetric across y = x.
static func _lane_wall_points(out: PackedVector2Array, lane: Array, sign: float) -> void:
	var travelled := 0.0
	for i in lane.size() - 1:
		var a: Vector2 = lane[i]
		var b: Vector2 = lane[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 1.0:
			continue
		var dir := seg / length
		var normal := Vector2(-dir.y, dir.x) * sign
		var t := 0.0
		while t < length:
			var p := a + dir * t + normal * LANE_WALL_OFFSET
			t += WALL_STEP
			travelled += WALL_STEP
			if fmod(travelled, WALL_GAP_PERIOD) < WALL_GAP_SPAN:
				continue  # a gank opening
			if p.y < p.x:
				continue  # team 1's half — paired by the mirror below
			if _dist_to_polyline(p, RIVER) < WALL_RIVER_CLEAR:
				continue
			if _dist_to_structures(p) < WALL_STRUCT_CLEAR:
				continue
			if _dist_to_spawns(p) < WALL_SPAWN_CLEAR:
				continue
			out.append(p)
			out.append(mirror(p))


## Rings a neutral camp with blocker points CAMP_POCKET_RADIUS out, leaving the arc toward the map
## centre open as the single entrance, and skipping any point on a lane or in the river. Each kept
## point is paired with its mirror so an off-axis camp's pocket and its partner camp's match, and
## an on-axis camp's pocket comes out symmetric.
static func _camp_pocket_points(out: PackedVector2Array, camp: Vector2) -> void:
	var gap_dir := -camp.normalized() if camp.length() > 0.1 else Vector2.RIGHT
	for i in CAMP_POCKET_POINTS:
		var ang := TAU * float(i) / float(CAMP_POCKET_POINTS)
		var d := Vector2(cos(ang), sin(ang))
		if d.dot(gap_dir) > CAMP_POCKET_GAP:
			continue  # the entrance opening toward the centre
		var p := camp + d * CAMP_POCKET_RADIUS
		if _dist_to_lanes(p) < CAMP_FEATURE_CLEAR or _dist_to_polyline(p, RIVER) < CAMP_FEATURE_CLEAR:
			continue
		if _dist_to_spawns(p) < WALL_SPAWN_CLEAR:
			continue
		out.append(p)
		out.append(mirror(p))


## Whether a unit of the given body radius standing at `p` would overlap any obstacle — used by the
## chase router and the nav-grid bake to test a point for free space.
static func point_blocked(p: Vector2, body_radius: float) -> bool:
	for o in obstacles():
		if p.distance_to(o["center"]) < o["radius"] + body_radius:
			return true
	return false


## Resolves a desired move out of the obstacles: given the step from `from` to `to`, pushes `to`
## back to the surface of any obstacle it would enter, keeping the tangential slide along it. A few
## passes settle the overlapping circles of a wall and its corners. Pure and deterministic — the
## same math the server and a predicting client both run, so reconciliation lands exactly. `to` is
## assumed already inside the map bounds.
static func slide(from: Vector2, to: Vector2, body_radius: float) -> Vector2:
	var pos := to
	for _pass in 4:
		var moved := false
		for o in obstacles():
			var center: Vector2 = o["center"]
			var min_dist: float = o["radius"] + body_radius
			var offset := pos - center
			var dist := offset.length()
			if dist >= min_dist:
				continue
			if dist > 0.0001:
				pos = center + offset / dist * min_dist  # out to the surface, keeping the slide
			else:
				var away := (from - center)
				away = away.normalized() if away.length() > 0.0001 else Vector2.RIGHT
				pos = center + away * min_dist
			moved = true
		if not moved:
			break
	return pos


## The shortest distance from `p` to any of the map's structures (towers and nexuses) — the
## clearance the wall generator keeps so a rock never swallows a building.
static func _dist_to_structures(p: Vector2) -> float:
	var best := INF
	for team in NEXUS_POSITIONS.size():
		for slot in tower_positions(team):
			best = minf(best, p.distance_to(slot))
		best = minf(best, p.distance_to(nexus_for_team(team)))
	return best


## The shortest distance from `p` to either team's base fountain — the clearance the walls keep so
## no rock ever boxes a team in at spawn.
static func _dist_to_spawns(p: Vector2) -> float:
	var best := INF
	for team in NEXUS_POSITIONS.size():
		best = minf(best, p.distance_to(spawn_for_team(team)))
	return best


## The shortest distance from `p` to any lane corridor — the clearance the camp pockets keep so a
## pocket rock never lands on a travelled lane.
static func _dist_to_lanes(p: Vector2) -> float:
	var best := INF
	for lane in LANES:
		best = minf(best, _dist_to_polyline(p, lane))
	return best


## The shortest distance from `p` to a polyline (a lane or the river), as the minimum over its
## segments. A point-to-segment distance, projected and clamped to each segment.
static func _dist_to_polyline(p: Vector2, poly: Array) -> float:
	var best := INF
	for i in poly.size() - 1:
		best = minf(best, _dist_to_segment(p, poly[i], poly[i + 1]))
	return best


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
