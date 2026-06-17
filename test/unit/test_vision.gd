extends GutTest
## Contracts for the per-team fog-of-war vision. Vision is pure data over a SimState — no engine,
## socket, or render coupling — so these run headless and deterministically, exactly like the
## simulation and map-data tests. They pin the two properties the netcode and the renderer lean on:
## a team always sees its own units, and an enemy is seen only when it stands inside a friendly
## sight source's radius — and that the rule is team-fair (mirror-symmetric).


## A bare world with the wave schedule off, so a test seats exactly the units it asserts on.
func _world() -> SimCore:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	return sim


func test_own_team_is_always_visible_even_out_of_sight_range() -> void:
	var sim := _world()
	var near_hero := sim.add_hero(0, Vector2.ZERO, 320.0)
	# A second friendly well beyond the first's sight radius — own units are seen regardless.
	var far_hero := sim.add_hero(0, Vector2(Vision.HERO_SIGHT * 4.0, 0.0), 320.0)
	var visible := Vision.visible_ids(sim.state, 0)
	assert_true(visible.has(near_hero), "a team always sees its own hero")
	assert_true(visible.has(far_hero), "a team sees its own hero even out of every sight radius")


func test_an_enemy_is_seen_only_inside_a_sight_radius() -> void:
	var sim := _world()
	sim.add_hero(0, Vector2.ZERO, 320.0)
	var seen := sim.add_entity(1, Vector2(Vision.HERO_SIGHT - 1.0, 0.0), 320.0, 100)
	var hidden := sim.add_entity(1, Vector2(Vision.HERO_SIGHT + 1.0, 0.0), 320.0, 100)
	var visible := Vision.visible_ids(sim.state, 0)
	assert_true(visible.has(seen), "an enemy just inside a hero's sight is visible")
	assert_false(visible.has(hidden), "an enemy just outside every sight radius stays in fog")


func test_a_creep_grants_vision() -> void:
	var sim := _world()
	sim.add_creep(0, 0, Vector2.ZERO)
	var enemy := sim.add_entity(1, Vector2(Vision.CREEP_SIGHT - 1.0, 0.0), 320.0, 100)
	assert_true(Vision.visible_ids(sim.state, 0).has(enemy), "a lane creep lights its front")


func test_a_structure_grants_vision() -> void:
	var sim := _world()
	sim.add_structure(0, Vector2.ZERO, 1000, 0, 0.0, 0)
	var enemy := sim.add_entity(1, Vector2(Vision.STRUCTURE_SIGHT - 1.0, 0.0), 320.0, 100)
	assert_true(Vision.visible_ids(sim.state, 0).has(enemy), "a tower holds a ward over its approach")


func test_a_downed_hero_grants_no_vision() -> void:
	var sim := _world()
	var hero := sim.add_hero(0, Vector2.ZERO, 320.0)
	sim.state.get_entity(hero).respawn_ticks = 100  # downed and on the respawn clock
	var enemy := sim.add_entity(1, Vector2(Vision.HERO_SIGHT - 1.0, 0.0), 320.0, 100)
	var visible := Vision.visible_ids(sim.state, 0)
	assert_true(visible.has(hero), "a team still sees its own downed hero")
	assert_false(visible.has(enemy), "a dead hero's ward goes dark — the enemy by its body is unseen")
	assert_eq(Vision.sight_sources(sim.state, 0).size(), 0, "a downed hero is not a sight source")


func test_sight_sources_lists_living_friendly_units_only() -> void:
	var sim := _world()
	var living := sim.add_hero(0, Vector2(120.0, -40.0), 320.0)
	var downed := sim.add_hero(0, Vector2(900.0, 0.0), 320.0)
	sim.state.get_entity(downed).respawn_ticks = 100
	sim.add_hero(1, Vector2.ZERO, 320.0)  # an enemy — never our source
	var sources := Vision.sight_sources(sim.state, 0)
	assert_eq(sources.size(), 1, "only the living friendly hero is a source")
	var pos := sim.state.get_entity(living).position
	assert_eq(sources[0]["center"], pos, "the source sits on the unit")
	assert_eq(sources[0]["radius"], Vision.HERO_SIGHT, "a hero's source carries the sight radius")


func test_a_wall_on_the_sight_line_hides_an_enemy_in_range() -> void:
	# Locate a real sight blocker and straddle it: a friendly source one side, the enemy the other,
	# close enough to be in range — the wall sitting between them must hide the enemy (the gank).
	var blockers := MapData.vision_blockers()
	assert_gt(blockers.size(), 0, "the map has sight-blocking walls")
	var wall: Dictionary = blockers[0]
	var center: Vector2 = wall["center"]
	var radius: float = wall["radius"]
	var sim := _world()
	sim.add_hero(0, center - Vector2.RIGHT * (radius + 30.0), 320.0)
	var enemy := sim.add_entity(1, center + Vector2.RIGHT * (radius + 30.0), 320.0, 100)
	assert_false(Vision.visible_ids(sim.state, 0).has(enemy), "a wall on the sight line hides it")


func test_a_clear_sight_line_sees_an_enemy_in_range() -> void:
	# Near a base fountain the walls keep their distance (WALL_SPAWN_CLEAR), so the sight line is
	# open — an in-range enemy with no wall between is seen, the counterpart to the occlusion above.
	var sim := _world()
	var base := MapData.spawn_for_team(0)
	sim.add_hero(0, base, 320.0)
	var enemy := sim.add_entity(1, base - base.normalized() * 150.0, 320.0, 100)
	assert_true(Vision.visible_ids(sim.state, 0).has(enemy), "a clear in-range enemy is seen")


func test_visible_ids_stays_cheap_over_a_heavy_world() -> void:
	# A slideshow tripwire, not a microbenchmark: the LOS occlusion scans the wall set, and the pass
	# runs a few times per tick (snapshot filter + render hide + minimap), so a full world must
	# resolve well inside the tick budget. The auto-pathing slice taught this lesson the hard way.
	var sim := _heavy_world()
	var start := Time.get_ticks_usec()
	for _i in 200:
		Vision.visible_ids(sim.state, 0)
	var per_call_us := float(Time.get_ticks_usec() - start) / 200.0
	print("visible_ids per call over a heavy world: %.1f us" % per_call_us)
	assert_lt(per_call_us, 2000.0, "visible_ids over a heavy world stays well under 2 ms/call")


func test_vision_is_team_fair_under_the_map_mirror() -> void:
	# The same encounter mirrored across the y = x axis and with the teams swapped must resolve the
	# same way — neither team sees farther, so fog never favours a side.
	var hero_pos := Vector2(0.0, 0.0)
	var enemy_pos := Vector2(500.0, 0.0)  # inside HERO_SIGHT

	var a := _world()
	a.add_hero(0, hero_pos, 320.0)
	var enemy_a := a.add_entity(1, enemy_pos, 320.0, 100)

	var b := _world()
	b.add_hero(1, MapData.mirror(hero_pos), 320.0)
	var enemy_b := b.add_entity(0, MapData.mirror(enemy_pos), 320.0, 100)

	assert_true(Vision.visible_ids(a.state, 0).has(enemy_a), "team 0 sees the enemy in range")
	assert_true(
		Vision.visible_ids(b.state, 1).has(enemy_b),
		"the mirrored encounter resolves identically for the swapped team",
	)


## A full mid-match world for the perf guard: both teams' structures, three heroes a side, and the
## opening creep waves on every lane (the first wave spawns on tick 0, so one step seeds it).
func _heavy_world() -> SimCore:
	var sim := SimCore.new()
	sim.spawn_structures()
	for team in 2:
		for i in 3:
			sim.add_hero(team, MapData.squad_spawn(team, i, 3), 320.0)
	sim.step({})
	return sim
