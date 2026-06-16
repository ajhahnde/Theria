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
