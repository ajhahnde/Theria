extends GutTest
## Contracts for the corner minimap. The drawing itself is judged in a playtest, but the two
## headless-safe pieces are pinned here: the sim-to-panel coordinate mapping (pure, so the plan
## lines up with the arena), and that build + per-tick update run without error over a real world.


func test_map_point_maps_the_arena_corners_to_the_panel() -> void:
	var panel := Vector2(Minimap.SIZE, Minimap.SIZE)
	var bounds := MapData.BOUNDS
	assert_eq(Minimap.map_point(bounds.position, panel), Vector2.ZERO, "top-left maps to 0")
	assert_eq(Minimap.map_point(bounds.end, panel), panel, "bottom-right maps to size")
	assert_eq(Minimap.map_point(bounds.get_center(), panel), panel * 0.5, "centre maps to centre")


func test_build_and_update_run_over_a_real_world() -> void:
	var minimap := Minimap.new()
	add_child_autofree(minimap)  # _ready pins the corner anchors
	var sim := SimCore.new()
	sim.spawn_structures()
	var hero := sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	sim.add_hero(1, MapData.spawn_for_team(1), 300.0)
	var focus := sim.state.get_entity(hero)
	# Local-authority path (filters enemy dots by vision) and the pure-CLIENT path (shows all).
	minimap.update(sim.state, 0, focus, [Color.RED, Color.BLUE], true)
	minimap.update(sim.state, 0, focus, [Color.RED, Color.BLUE], false)
	# Before a hero spawns the driver passes a null focus — must not error.
	minimap.update(sim.state, 0, null, [Color.RED, Color.BLUE], true)
	assert_eq(minimap.custom_minimum_size, Vector2(Minimap.SIZE, Minimap.SIZE), "the panel is sized")
