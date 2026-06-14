extends GutTest
## Deterministic checks on the authoritative simulation core. These run headless
## and stay free of any engine/render coupling — they exercise the exact step
## function the live client and (later) the netcode drive.


func test_constant_input_advances_position_deterministically() -> void:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2.ZERO, 300.0)
	var command := InputCommand.new()
	command.move_dir = Vector2.RIGHT
	var inputs := {id: command}
	for _i in SimCore.TICK_RATE:
		sim.step(inputs)
	var entity := sim.state.get_entity(id)
	# 60 ticks * (1/60 s) * 300 u/s = 300 units along +x.
	assert_almost_eq(entity.position.x, 300.0, 0.0001)
	assert_almost_eq(entity.position.y, 0.0, 0.0001)
	assert_eq(sim.state.tick, 60)


func test_identical_input_replays_identically() -> void:
	var a := _run_scripted(120)
	var b := _run_scripted(120)
	assert_eq(a, b, "the simulation must be a pure function of state + input")


func test_diagonal_input_is_not_faster() -> void:
	var sim := SimCore.new()
	var speed := 300.0
	var id := sim.add_entity(0, Vector2.ZERO, speed)
	var command := InputCommand.new()
	command.move_dir = Vector2.ONE  # length sqrt(2) -> must clamp to 1
	sim.step({id: command})
	var moved := sim.state.get_entity(id).position.length()
	assert_almost_eq(moved, speed * SimCore.TICK_DELTA, 0.0001)


func test_entity_without_command_holds_still() -> void:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2(10.0, -5.0), 300.0)
	sim.step({})
	assert_eq(sim.state.get_entity(id).position, Vector2(10.0, -5.0))


func _run_scripted(ticks: int) -> Vector2:
	var sim := SimCore.new()
	var id := sim.add_entity(0, Vector2.ZERO, 250.0)
	var command := InputCommand.new()
	for i in ticks:
		command.move_dir = Vector2(sin(float(i)), cos(float(i)))
		sim.step({id: command})
	return sim.state.get_entity(id).position


# --- Combat: towers, structures, and the win condition ----------------------


func test_structure_strikes_an_enemy_in_range() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 550, "an in-range enemy takes attack_damage")


func test_structure_ignores_an_enemy_out_of_range() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(300.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 600, "an out-of-range enemy is untouched")


func test_structure_does_not_strike_an_ally() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var ally := sim.add_entity(0, Vector2(100.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(ally).hp, 600, "an attacker never hits its own team")


func test_attack_respects_its_cooldown() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	for _i in 60:
		sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 550, "one hit lands across a full cooldown window")
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 500, "the cooldown elapses next tick, second hit lands")


func test_an_entity_dies_when_its_hp_reaches_zero() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 1000, 100, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 100)
	sim.step({})
	assert_null(sim.state.get_entity(enemy), "an entity at 0 hp is removed from the world")


func test_nexus_destruction_sets_the_winner_and_freezes_the_match() -> void:
	var sim := SimCore.new()
	sim.add_structure(0, Vector2.ZERO, 100, 0, 0.0, 0, true)  # team 0 nexus
	# A team 1 attacker in range (a stand-in for the creeps that arrive next).
	sim.add_structure(1, Vector2(100.0, 0.0), 1000, 100, 200.0, 60)
	sim.step({})
	assert_true(sim.state.is_match_over(), "a destroyed nexus ends the match")
	assert_eq(sim.state.winner, 1, "the other team wins")
	var frozen_tick := sim.state.tick
	sim.step({})
	assert_eq(sim.state.tick, frozen_tick, "the simulation no-ops once the match is over")


func test_spawn_structures_is_mirror_fair() -> void:
	var sim := SimCore.new()
	sim.spawn_structures()
	# Every team 0 structure must have a team 1 structure at the negated position
	# with the same role and health, so neither side starts ahead.
	for id in sim.state.entities:
		var s: SimEntity = sim.state.entities[id]
		if s.team != 0:
			continue
		var mirror := _structure_at(sim.state, 1, -s.position)
		assert_not_null(mirror, "team 0's structure must have a mirrored team 1 counterpart")
		if mirror != null:
			assert_eq(mirror.is_nexus, s.is_nexus, "the mirrored structure must share its role")
			assert_eq(mirror.max_hp, s.max_hp, "the mirrored structure must share its health")


func _structure_at(state: SimState, team: int, position: Vector2) -> SimEntity:
	for id in state.entities:
		var s: SimEntity = state.entities[id]
		if s.team == team and s.is_structure and s.position.is_equal_approx(position):
			return s
	return null


func test_a_combat_run_replays_identically() -> void:
	var a := _run_combat()
	var b := _run_combat()
	assert_eq(a, b, "combat must be a pure function of state + input")


func _run_combat() -> Array:
	var sim := SimCore.new()
	sim.spawn_structures()
	var hero := sim.add_entity(0, MapData.spawn_for_team(0), 320.0, 600)
	var bot := sim.add_entity(1, MapData.spawn_for_team(1), 300.0, 600)
	var march := InputCommand.new()
	march.move_dir = Vector2(1.0, -1.0)  # walk both units toward the enemy base
	for _i in 600:
		sim.step({hero: march, bot: march})
	return _snapshot(sim.state)


## A deterministic, comparable digest of the world: every surviving entity's id,
## hp, and rounded position, ordered by id.
func _snapshot(state: SimState) -> Array:
	var ids := state.entities.keys()
	ids.sort()
	var rows: Array = []
	for id in ids:
		var entity: SimEntity = state.entities[id]
		rows.append([id, entity.hp, entity.position.round()])
	return rows
