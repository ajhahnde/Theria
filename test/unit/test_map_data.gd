extends GutTest
## Geometry contracts for the 3v3 arena. These pin the map's mirror-fairness across the y = x
## axis and the lane orientation the creep layer depends on. Pure data checks — no engine or
## render coupling, the same discipline as the sim-core tests.


func test_mirror_swaps_components_and_is_its_own_inverse() -> void:
	var p := Vector2(120.0, -340.0)
	assert_eq(MapData.mirror(p), Vector2(-340.0, 120.0), "the mirror reflects across y = x")
	assert_eq(MapData.mirror(MapData.mirror(p)), p, "mirroring twice returns the original point")


func test_nexuses_are_axially_symmetric_and_in_bounds() -> void:
	var n0 := MapData.nexus_for_team(0)
	var n1 := MapData.nexus_for_team(1)
	assert_eq(n1, MapData.mirror(n0), "team 1's nexus must be team 0's nexus mirrored across y = x")
	assert_eq(MapData.clamp_to_bounds(n0), n0, "nexus 0 must sit inside the bounds")
	assert_eq(MapData.clamp_to_bounds(n1), n1, "nexus 1 must sit inside the bounds")


func test_team_fountains_sit_at_base_and_mirror_across_the_axis() -> void:
	var f0 := MapData.spawn_for_team(0)
	var f1 := MapData.spawn_for_team(1)
	assert_eq(f1, MapData.mirror(f0), "team 1's fountain must be team 0's fountain mirrored")
	assert_eq(MapData.clamp_to_bounds(f0), f0, "the fountain must sit inside the bounds")
	# It is at base: closer to its own nexus than to the map centre.
	var nexus := MapData.nexus_for_team(0)
	assert_true(
		f0.distance_to(nexus) < f0.length(),
		"a fountain spawns at its base, not out near the centre",
	)


func test_lane_path_orients_from_each_team_nexus_to_the_enemy_nexus() -> void:
	for lane in MapData.lane_count():
		var team0 := MapData.lane_path(lane, 0)
		var team1 := MapData.lane_path(lane, 1)
		assert_eq(team0[0], MapData.nexus_for_team(0), "team 0 starts at its own nexus")
		assert_eq(team0[team0.size() - 1], MapData.nexus_for_team(1), "team 0 ends at the enemy nexus")
		assert_eq(team1[0], MapData.nexus_for_team(1), "team 1 starts at its own nexus")
		assert_eq(team1[team1.size() - 1], MapData.nexus_for_team(0), "team 1 ends at the enemy nexus")


func test_lane_path_for_each_team_is_the_reverse_of_the_other() -> void:
	for lane in MapData.lane_count():
		var forward := MapData.lane_path(lane, 0)
		var reversed := MapData.lane_path(lane, 1)
		reversed.reverse()
		assert_eq(forward, reversed, "a corridor is one path walked in opposite directions")


func test_lane_path_returns_a_fresh_copy() -> void:
	var first := MapData.lane_path(0, 0)
	first.reverse()
	var second := MapData.lane_path(0, 0)
	assert_ne(first, second, "mutating a returned path must not alter the stored geometry")


func test_each_lane_is_its_own_axial_reflection() -> void:
	# Mirror-and-reverse must map each corridor onto itself, so the two teams walk a lane the
	# same way and neither has a shorter or safer route.
	for lane in MapData.lane_count():
		var path := MapData.lane_path(lane, 0)
		var mirrored := PackedVector2Array()
		for i in range(path.size() - 1, -1, -1):
			mirrored.append(MapData.mirror(path[i]))
		assert_eq(mirrored, path, "each lane must be its own reflection across the y = x axis")


func test_jungle_camps_are_closed_under_the_axis_mirror_and_in_bounds() -> void:
	var camps := MapData.JUNGLE_CAMPS
	for camp in camps:
		assert_eq(MapData.clamp_to_bounds(camp), camp, "every camp must sit inside the bounds")
		assert_true(camps.has(MapData.mirror(camp)), "every camp must have a mirror partner across y = x")


func test_two_jungle_camps_are_neutral_on_the_axis() -> void:
	# The camps sitting on the y = x axis are their own mirror — the shared, team-neutral camps.
	# The map has exactly two; the rest are off-axis mirror pairs, one per side.
	var neutral := 0
	for camp in MapData.JUNGLE_CAMPS:
		if is_equal_approx(camp.x, camp.y):
			neutral += 1
	assert_eq(neutral, 2, "exactly two jungle camps are neutral (on the y = x axis)")


func test_tower_positions_are_axially_symmetric_between_teams() -> void:
	var team0 := MapData.tower_positions(0)
	var team1 := MapData.tower_positions(1)
	assert_eq(team0.size(), team1.size(), "both teams field the same number of towers")
	for i in team0.size():
		assert_eq(team1[i], MapData.mirror(team0[i]), "team 1's towers must be team 0's mirrored")


func test_tower_positions_are_in_bounds() -> void:
	for team in MapData.NEXUS_POSITIONS.size():
		for tower in MapData.tower_positions(team):
			assert_eq(MapData.clamp_to_bounds(tower), tower, "every tower must sit inside the bounds")


func test_tower_positions_returns_a_fresh_copy() -> void:
	var first := MapData.tower_positions(0)
	first[0] = Vector2.ZERO
	var second := MapData.tower_positions(0)
	assert_ne(first[0], second[0], "mutating a returned tower list must not alter the stored slots")


func test_squad_spawn_of_one_falls_back_to_the_fountain() -> void:
	for team in MapData.NEXUS_POSITIONS.size():
		assert_eq(
			MapData.squad_spawn(team, 0, 1),
			MapData.spawn_for_team(team),
			"a squad of one spawns on the bare fountain",
		)


func test_squad_spawn_fans_a_team_into_distinct_in_bounds_seats() -> void:
	var count := 3
	for team in MapData.NEXUS_POSITIONS.size():
		var seen: Array[Vector2] = []
		for i in count:
			var seat := MapData.squad_spawn(team, i, count)
			assert_eq(MapData.clamp_to_bounds(seat), seat, "every squad seat sits inside the bounds")
			assert_false(seen.has(seat), "squadmates spawn on distinct points, not stacked")
			seen.append(seat)


func test_squad_spawn_is_axially_symmetric_between_teams() -> void:
	var count := 3
	for i in count:
		assert_eq(
			MapData.squad_spawn(1, i, count),
			MapData.mirror(MapData.squad_spawn(0, i, count)),
			"team 1's squad seat must be team 0's mirrored, so neither side has an edge",
		)


func test_squad_spawn_fan_is_centred_on_the_fountain() -> void:
	# The fan is symmetric about the fountain, so the seats average back to it.
	var count := 3
	var sum := Vector2.ZERO
	for i in count:
		sum += MapData.squad_spawn(0, i, count)
	var centre := sum / float(count)
	assert_almost_eq(
		centre, MapData.spawn_for_team(0), Vector2(0.01, 0.01), "the squad fan centres on the fountain"
	)


func test_river_is_axially_symmetric_and_in_bounds() -> void:
	# Mirror-and-reverse must map the river onto itself, so it divides the map evenly and
	# neither team has more water in its half.
	var river := MapData.river_polyline()
	var mirrored := PackedVector2Array()
	for i in range(river.size() - 1, -1, -1):
		mirrored.append(MapData.mirror(river[i]))
	assert_eq(mirrored, river, "the river must be its own reflection across the y = x axis")
	for point in river:
		assert_eq(MapData.clamp_to_bounds(point), point, "every river point sits inside the bounds")


func test_river_polyline_returns_a_fresh_copy() -> void:
	var first := MapData.river_polyline()
	first.reverse()
	var second := MapData.river_polyline()
	assert_ne(first, second, "mutating the returned river must not alter the stored course")


func test_each_team_holds_four_towers() -> void:
	# Two towers ring the nexus and two stand forward down the lanes — four a side, mirrored.
	assert_eq(MapData.tower_positions(0).size(), 4, "each team fields four towers")
	assert_eq(MapData.tower_positions(1).size(), 4, "both teams field the same count")
