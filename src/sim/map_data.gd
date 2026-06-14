class_name MapData
extends RefCounted
## Static geometry for the 3v3 arena.
##
## The map is point-symmetric through the origin: team 1's geometry is team 0's
## negated, so every structure has a mirrored counterpart and neither side has a
## positional edge. The simulation reads this layer as pure data — bounds, the
## team bases, the lane corridors, and the neutral jungle camps — with no engine
## or render coupling, so bots, tests, and (later) the netcode share one source
## of truth.

## Playable area, in world units, centred on the origin.
const BOUNDS := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)

## The nexus position for each team, indexed by team id. The nexus is the win
## condition (destroyed to end the match) and the inner anchor both lane
## corridors converge on at a base. Point-symmetric: index 1 is index 0 negated.
const NEXUS_POSITIONS: Array[Vector2] = [
	Vector2(-1600.0, 1600.0),
	Vector2(1600.0, -1600.0),
]

## Hero spawn position for each team, indexed by team id.
##
## These are the v0.1 walking-skeleton spawns near the centre, kept stable so the
## skeleton demo is undisturbed by this layer. Aligning spawns to a fountain at
## each base is a later slice (it lands with the client camera that frames the
## full map); the base anchor for that work is `NEXUS_POSITIONS`.
const TEAM_SPAWNS: Array[Vector2] = [
	Vector2(-360.0, -200.0),
	Vector2(360.0, 200.0),
]

## Top corridor: out of team 0's base, up the left edge, across the top.
const LANE_TOP: Array[Vector2] = [
	Vector2(-1600.0, 1600.0),
	Vector2(-1600.0, -1600.0),
	Vector2(1600.0, -1600.0),
]

## Bottom corridor: out of team 0's base, across the bottom, up the right edge.
const LANE_BOTTOM: Array[Vector2] = [
	Vector2(-1600.0, 1600.0),
	Vector2(1600.0, 1600.0),
	Vector2(1600.0, -1600.0),
]

## The lane corridors, each a polyline stored from team 0's nexus to team 1's
## nexus. Both teams push both corridors in opposite directions; `lane_path`
## orients a corridor for a given team's travel. The two corridors are point
## reflections of each other (negate-and-reverse maps one onto the other), so the
## map stays mirror-fair. v0.1 is two lanes plus the jungle — there is no mid.
const LANES: Array[Array] = [LANE_TOP, LANE_BOTTOM]

## Neutral jungle camp positions in the open band between the lanes. Closed under
## negation (every camp has a mirrored partner; the centre camp is its own), so
## the neutral layer is symmetric like the rest of the map.
const JUNGLE_CAMPS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(-500.0, -500.0),
	Vector2(500.0, 500.0),
	Vector2(500.0, -500.0),
	Vector2(-500.0, 500.0),
]

## Defensive tower slots for team 0: two per lane, sitting on the lane segment
## that leaves team 0's base, so each corridor is guarded on the way in. Team 1's
## slots are these negated (see `tower_positions`), which — because the lane set
## is closed under point reflection — also land on the lanes, by team 1's base.
## Every slot lies exactly on a lane polyline segment and inside the bounds.
const TOWER_SLOTS_TEAM0: Array[Vector2] = [
	Vector2(-1600.0, 800.0),
	Vector2(-1600.0, -800.0),
	Vector2(-800.0, 1600.0),
	Vector2(800.0, 1600.0),
]


static func spawn_for_team(team: int) -> Vector2:
	return TEAM_SPAWNS[team % TEAM_SPAWNS.size()]


static func nexus_for_team(team: int) -> Vector2:
	return NEXUS_POSITIONS[team % NEXUS_POSITIONS.size()]


## The tower slots for `team`: team 0's stored slots, negated for team 1 so the
## two teams' defences are point reflections of each other. Returns a fresh copy
## so callers cannot mutate the stored geometry.
static func tower_positions(team: int) -> PackedVector2Array:
	var slots := PackedVector2Array(TOWER_SLOTS_TEAM0)
	if team % 2 == 1:
		for i in slots.size():
			slots[i] = -slots[i]
	return slots


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


static func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, BOUNDS.position.x, BOUNDS.end.x),
		clampf(pos.y, BOUNDS.position.y, BOUNDS.end.y),
	)
