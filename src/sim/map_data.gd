class_name MapData
extends RefCounted
## Static geometry for the 3v3 arena.
##
## v0.1 walking skeleton: a single bounded play field with one spawn per team.
## Lane and jungle layout layers on later as data; the only contract the
## simulation relies on now is the playable bounds and the team spawns.

## Playable area, in world units, centred on the origin.
const BOUNDS := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)

## Spawn position for each team, indexed by team id.
const TEAM_SPAWNS: Array[Vector2] = [
	Vector2(-360.0, -200.0),
	Vector2(360.0, 200.0),
]


static func spawn_for_team(team: int) -> Vector2:
	return TEAM_SPAWNS[team % TEAM_SPAWNS.size()]


static func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, BOUNDS.position.x, BOUNDS.end.x),
		clampf(pos.y, BOUNDS.position.y, BOUNDS.end.y),
	)
