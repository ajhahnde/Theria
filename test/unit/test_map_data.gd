extends GutTest
## Geometry contracts for the 3v3 arena. These pin the map's mirror-fairness and
## the lane orientation the creep layer will depend on. Pure data checks — no
## engine or render coupling, the same discipline as the sim-core tests.


func test_nexuses_are_point_symmetric_and_in_bounds() -> void:
	var n0 := MapData.nexus_for_team(0)
	var n1 := MapData.nexus_for_team(1)
	assert_eq(n1, -n0, "team 1's nexus must be team 0's nexus negated")
	assert_eq(MapData.clamp_to_bounds(n0), n0, "nexus 0 must sit inside the bounds")
	assert_eq(MapData.clamp_to_bounds(n1), n1, "nexus 1 must sit inside the bounds")


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


func test_lanes_are_point_reflections_of_each_other() -> void:
	# Negate-and-reverse must map the set of corridors onto itself, so the two
	# lanes are mirror images and neither team has a shorter or safer route.
	var canon: Array[PackedVector2Array] = []
	for lane in MapData.lane_count():
		canon.append(MapData.lane_path(lane, 0))
	for path in canon:
		var mirrored := PackedVector2Array()
		for i in range(path.size() - 1, -1, -1):
			mirrored.append(-path[i])
		var found := false
		for other in canon:
			if other == mirrored:
				found = true
				break
		assert_true(found, "every lane's point reflection must also be a lane")


func test_jungle_camps_are_closed_under_negation_and_in_bounds() -> void:
	var camps := MapData.JUNGLE_CAMPS
	for camp in camps:
		assert_eq(MapData.clamp_to_bounds(camp), camp, "every camp must sit inside the bounds")
		assert_true(camps.has(-camp), "every camp must have a mirrored partner (negated)")


func test_tower_positions_are_point_symmetric_between_teams() -> void:
	var team0 := MapData.tower_positions(0)
	var team1 := MapData.tower_positions(1)
	assert_eq(team0.size(), team1.size(), "both teams field the same number of towers")
	for i in team0.size():
		assert_eq(team1[i], -team0[i], "team 1's towers must be team 0's towers negated")


func test_tower_positions_returns_a_fresh_copy() -> void:
	var first := MapData.tower_positions(0)
	first[0] = Vector2.ZERO
	var second := MapData.tower_positions(0)
	assert_ne(first[0], second[0], "mutating a returned tower list must not alter the stored slots")


func test_every_tower_sits_on_a_lane_and_inside_the_bounds() -> void:
	for team in MapData.NEXUS_POSITIONS.size():
		for tower in MapData.tower_positions(team):
			assert_eq(MapData.clamp_to_bounds(tower), tower, "every tower must sit inside the bounds")
			var on_a_lane := false
			for lane in MapData.lane_count():
				if _point_on_polyline(tower, MapData.lane_path(lane, 0)):
					on_a_lane = true
					break
			assert_true(on_a_lane, "every tower must sit on a lane corridor")


## True when `point` lies on one of the polyline's segments (within a small
## tolerance): the segment endpoints span it and it is collinear with them.
func _point_on_polyline(point: Vector2, path: PackedVector2Array) -> bool:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var ab := b - a
		var ap := point - a
		if absf(ab.cross(ap)) > 0.01:
			continue
		var t := ap.dot(ab) / ab.length_squared()
		if t >= 0.0 and t <= 1.0:
			return true
	return false
