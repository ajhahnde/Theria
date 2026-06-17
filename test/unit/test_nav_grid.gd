extends GutTest
## The deterministic grid pathfinder. These pin the routing contract the client and the bots lean
## on: a clear line is a straight shot, a blocked line routes around the obstacle on a
## collision-free path, a target inside an obstacle resolves to free ground, and the same query
## always yields the same path (so a bot's route replays identically). Pure data checks — no engine
## coupling, the same discipline as the rest of the sim tests.


func test_clear_line_is_a_direct_single_waypoint() -> void:
	var nav := NavGrid.new()
	var from := Vector2(0.0, 0.0)
	var to := Vector2(200.0, 0.0)  # open ground near the map centre
	var path := nav.find_path(from, to)
	assert_eq(path.size(), 1, "a clear line needs no intermediate waypoints")
	assert_eq(path[0], to, "the single waypoint is the destination itself")


func test_from_equals_to_returns_the_point() -> void:
	var nav := NavGrid.new()
	var p := Vector2(0.0, 0.0)
	var path := nav.find_path(p, p)
	assert_eq(path.size(), 1, "a zero-length move is one waypoint")
	assert_eq(path[0], p)


func test_routes_around_a_blocking_obstacle_on_a_clear_path() -> void:
	var nav := NavGrid.new()
	var center := MapData.tower_positions(0)[0]  # a real obstacle, open ground around it
	var from := center + Vector2(700.0, 0.0)
	var to := center - Vector2(700.0, 0.0)
	assert_false(nav.segment_clear(from, to), "the straight line must run through the obstacle")
	var path := nav.find_path(from, to)
	assert_gt(path.size(), 0, "a routable goal yields a path")
	# Every leg of the realised route (from the unit's position through the waypoints) is clear.
	var prev := from
	for w in path:
		assert_true(nav.segment_clear(prev, w), "each leg of the route avoids the obstacles")
		prev = w
	assert_lt(
		path[path.size() - 1].distance_to(to),
		NavGrid.CELL * 2.0,
		"the route ends on the requested destination",
	)


func test_target_inside_an_obstacle_resolves_to_free_ground() -> void:
	var nav := NavGrid.new()
	var center := MapData.tower_positions(0)[0]
	var from := center + Vector2(1000.0, 0.0)
	var path := nav.find_path(from, center)  # aim straight at the obstacle's centre
	assert_gt(path.size(), 0, "a blocked target still yields a path to its edge")
	var last := path[path.size() - 1]
	assert_false(
		MapData.point_blocked(last, SimCore.UNIT_RADIUS),
		"the route ends on free ground, not inside the obstacle",
	)


func test_same_query_yields_an_identical_path() -> void:
	var nav := NavGrid.new()
	var center := MapData.tower_positions(0)[0]
	var from := center + Vector2(700.0, 0.0)
	var to := center - Vector2(700.0, 0.0)
	var a := nav.find_path(from, to)
	var b := nav.find_path(from, to)
	assert_eq(a, b, "pathfinding is deterministic — the same query is byte-identical")


func test_each_spawn_can_route_toward_the_enemy_base() -> void:
	# The map stays traversable: a team can always route from its base to the enemy's.
	var nav := NavGrid.new()
	for team in MapData.NEXUS_POSITIONS.size():
		var path := nav.find_path(MapData.spawn_for_team(team), MapData.spawn_for_team(1 - team))
		assert_gt(path.size(), 0, "a team can route from its base toward the enemy base")
