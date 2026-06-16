extends GutTest
## Deterministic checks on the authoritative simulation core. These run headless
## and stay free of any engine/render coupling — they exercise the exact step
## function the live client and (later) the netcode drive.


func test_constant_input_advances_position_deterministically() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false  # isolate the movement assertion from the wave schedule
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
	sim.spawn_creeps = false
	var speed := 300.0
	var id := sim.add_entity(0, Vector2.ZERO, speed)
	var command := InputCommand.new()
	command.move_dir = Vector2.ONE  # length sqrt(2) -> must clamp to 1
	sim.step({id: command})
	var moved := sim.state.get_entity(id).position.length()
	assert_almost_eq(moved, speed * SimCore.TICK_DELTA, 0.0001)


func test_entity_without_command_holds_still() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := sim.add_entity(0, Vector2(10.0, -5.0), 300.0)
	sim.step({})
	assert_eq(sim.state.get_entity(id).position, Vector2(10.0, -5.0))


func _run_scripted(ticks: int) -> Vector2:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := sim.add_entity(0, Vector2.ZERO, 250.0)
	var command := InputCommand.new()
	for i in ticks:
		command.move_dir = Vector2(sin(float(i)), cos(float(i)))
		sim.step({id: command})
	return sim.state.get_entity(id).position


# --- Combat: towers, structures, and the win condition ----------------------


func test_structure_strikes_an_enemy_in_range() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 550, "an in-range enemy takes attack_damage")


func test_structure_ignores_an_enemy_out_of_range() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(300.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 600, "an out-of-range enemy is untouched")


func test_structure_does_not_strike_an_ally() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var ally := sim.add_entity(0, Vector2(100.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(sim.state.get_entity(ally).hp, 600, "an attacker never hits its own team")


func test_attack_respects_its_cooldown() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_structure(0, Vector2.ZERO, 1000, 50, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	for _i in 60:
		sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 550, "one hit lands across a full cooldown window")
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 500, "the cooldown elapses next tick, second hit lands")


func test_an_entity_dies_when_its_hp_reaches_zero() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_structure(0, Vector2.ZERO, 1000, 100, 200.0, 60)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 100)
	sim.step({})
	assert_null(sim.state.get_entity(enemy), "an entity at 0 hp is removed from the world")


# --- Hero death & respawn ---------------------------------------------------


func test_a_slain_hero_is_downed_not_erased() -> void:
	# Unlike a creep, a dead hero is kept in the world and put on the respawn clock, so its id and
	# countdown persist for the client's death screen and the revive step.
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var hero := sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	sim.state.get_entity(hero).hp = 0
	sim.step({})
	var downed := sim.state.get_entity(hero)
	assert_not_null(downed, "a slain hero stays in the world rather than being erased")
	assert_true(downed.is_dead(), "the slain hero is marked dead")
	assert_eq(downed.respawn_ticks, SimCore.HERO_RESPAWN_TICKS, "its respawn clock is started")
	assert_eq(downed.hp, 0, "a downed hero sits at 0 hp")


func test_a_downed_hero_respawns_full_at_its_spawn_point() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var spawn := MapData.spawn_for_team(0)
	var hero := sim.add_hero(0, spawn, 320.0)
	# Walk the hero off its spawn so the respawn-in-place is observable, then kill it.
	sim.state.get_entity(hero).position = spawn + Vector2(500.0, 0.0)
	sim.state.get_entity(hero).hp = 0
	sim.step({})  # downs the hero, starting the HERO_RESPAWN_TICKS countdown
	for _i in SimCore.HERO_RESPAWN_TICKS - 1:
		sim.step({})
		assert_true(sim.state.get_entity(hero).is_dead(), "the hero stays down until the timer elapses")
	sim.step({})  # the tick the timer reaches 0
	var revived := sim.state.get_entity(hero)
	assert_false(revived.is_dead(), "the hero is alive once the timer elapses")
	assert_eq(revived.hp, SimCore.HERO_HP, "it returns at full health")
	assert_eq(revived.position, spawn, "it returns at its spawn point")


func test_a_downed_hero_is_inert_and_untargetable() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var tower := sim.add_structure(1, Vector2.ZERO, 1000, 100, 300.0, 60)
	var hero := sim.add_hero(0, Vector2(100.0, 0.0), 320.0)
	sim.state.get_entity(hero).hp = 0
	sim.step({})  # downs the hero
	assert_true(sim.state.get_entity(hero).is_dead())
	var down_pos := sim.state.get_entity(hero).position
	# Untargetable: the only enemy in the tower's range is the corpse, so it finds nothing to hit.
	assert_null(
		sim._nearest_enemy_in_range(sim.state.get_entity(tower)),
		"a downed hero is not a valid attack target",
	)
	# Inert: a move command on a downed hero is ignored — it holds where it fell.
	var command := InputCommand.new()
	command.move_dir = Vector2.RIGHT
	sim.step({hero: command})
	assert_eq(sim.state.get_entity(hero).position, down_pos, "a downed hero does not move")


func test_nexus_destruction_sets_the_winner_and_freezes_the_match() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
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
	# Every team 0 structure must have a team 1 structure at the axially mirrored position
	# with the same role and health, so neither side starts ahead.
	for id in sim.state.entities:
		var s: SimEntity = sim.state.entities[id]
		if s.team != 0:
			continue
		var mirror := _structure_at(sim.state, 1, MapData.mirror(s.position))
		assert_not_null(mirror, "team 0's structure must have a mirrored team 1 counterpart")
		if mirror != null:
			assert_eq(mirror.is_nexus, s.is_nexus, "the mirrored structure must share its role")
			assert_eq(mirror.max_hp, s.max_hp, "the mirrored structure must share its health")


func test_spawn_structures_gives_each_team_a_nexus_and_four_towers() -> void:
	# A team's defences: one destructible nexus plus four towers — two ringing the nexus and
	# two forward down the lanes.
	var sim := SimCore.new()
	sim.spawn_structures()
	for team in MapData.NEXUS_POSITIONS.size():
		var nexuses := 0
		var towers := 0
		for id in sim.state.entities:
			var s: SimEntity = sim.state.entities[id]
			if not s.is_structure or s.team != team:
				continue
			if s.is_nexus:
				nexuses += 1
			else:
				towers += 1
		assert_eq(nexuses, 1, "a team has exactly one nexus")
		assert_eq(towers, 4, "a team fields four towers — two guarding the nexus, two forward")


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
	var hero := sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	var bot := sim.add_hero(1, MapData.spawn_for_team(1), 300.0)
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


# --- Creeps: lane marching, contact combat, and the wave schedule -----------


func test_a_creep_marches_its_lane_toward_the_enemy_nexus() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var path := MapData.lane_path(0, 0)
	var creep := sim.add_creep(0, 0, path[0])
	var start := sim.state.get_entity(creep).position
	for _i in SimCore.TICK_RATE:
		sim.step({})
	var here := sim.state.get_entity(creep).position
	assert_true(here.distance_to(start) > 0.0, "a creep with a clear lane keeps moving")
	assert_true(
		here.distance_to(path[1]) < start.distance_to(path[1]),
		"it advances toward its next waypoint",
	)


func test_a_creep_holds_position_to_fight_an_enemy_in_range() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var spawn := MapData.lane_path(0, 0)[0]
	var creep := sim.add_creep(0, 0, spawn)
	# An enemy parked just inside the creep's reach: the creep must stop to fight.
	var enemy := sim.add_entity(1, spawn + Vector2(SimCore.CREEP_RANGE - 10.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(
		sim.state.get_entity(creep).position,
		spawn,
		"a creep with an enemy in range holds to fight",
	)
	assert_eq(
		sim.state.get_entity(enemy).hp,
		600 - SimCore.CREEP_DAMAGE,
		"and strikes it through the shared combat primitive",
	)


func test_an_unopposed_creep_destroys_the_enemy_nexus_and_wins() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	# A team-1 nexus weak enough to fall to two creep hits, and a lone team-0 creep
	# already in range — the win condition driven entirely by a creep.
	var nexus := sim.add_structure(1, Vector2.ZERO, SimCore.CREEP_DAMAGE * 2, 0, 0.0, 0, true)
	sim.add_creep(0, 0, Vector2(SimCore.CREEP_RANGE - 10.0, 0.0))
	for _i in SimCore.CREEP_COOLDOWN_TICKS + 2:
		sim.step({})
	assert_null(sim.state.get_entity(nexus), "the creep's strikes destroy the enemy nexus")
	assert_true(sim.state.is_match_over(), "felling the nexus ends the match")
	assert_eq(sim.state.winner, 0, "the creep's team wins")


func test_creep_waves_spawn_on_the_wave_schedule() -> void:
	var sim := SimCore.new()  # spawn_creeps defaults on
	var per_wave := SimCore.CREEP_PER_WAVE * MapData.lane_count() * MapData.NEXUS_POSITIONS.size()
	sim.step({})  # tick 0 -> the opening wave
	assert_eq(
		_count_creeps(sim.state),
		per_wave,
		"a full wave spawns for both teams on every lane at tick 0",
	)
	# Clear the wave so the two teams' creeps can't clash and confound the count,
	# leaving the schedule the only thing that adds creeps.
	for id in sim.state.entities.keys():
		if sim.state.entities[id].is_creep:
			sim.state.entities.erase(id)
	for _i in SimCore.CREEP_WAVE_INTERVAL_TICKS - 1:
		sim.step({})
	assert_eq(_count_creeps(sim.state), 0, "no wave spawns between intervals")
	sim.step({})  # the next interval boundary
	assert_eq(_count_creeps(sim.state), per_wave, "the next wave spawns on the interval")


func test_creep_waves_are_mirror_fair() -> void:
	var sim := SimCore.new()
	sim.step({})  # spawn and advance the opening waves one tick
	for id in sim.state.entities:
		var creep: SimEntity = sim.state.entities[id]
		if not creep.is_creep or creep.team != 0:
			continue
		assert_not_null(
			_creep_at(sim.state, 1, MapData.mirror(creep.position)),
			"every team-0 creep has a team-1 creep mirrored across the y = x axis",
		)


# --- Heroes: the player/bot combat unit -------------------------------------


func test_a_hero_strikes_an_enemy_in_range() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var hero := sim.add_hero(0, Vector2.ZERO, 320.0)
	var enemy := sim.add_entity(1, Vector2(SimCore.HERO_RANGE - 10.0, 0.0), 0.0, 600)
	sim.step({})
	assert_eq(
		sim.state.get_entity(enemy).hp,
		600 - SimCore.HERO_DAMAGE,
		"a hero auto-attacks an enemy in range through the shared combat primitive",
	)
	# A hero out-hits a creep: its damage exceeds a creep's, so it clears waves.
	assert_true(SimCore.HERO_DAMAGE > SimCore.CREEP_DAMAGE, "a hero out-damages a creep")


func _count_creeps(state: SimState) -> int:
	var n := 0
	for id in state.entities:
		if state.entities[id].is_creep:
			n += 1
	return n


func _creep_at(state: SimState, team: int, position: Vector2) -> SimEntity:
	for id in state.entities:
		var creep: SimEntity = state.entities[id]
		if creep.is_creep and creep.team == team and creep.position.is_equal_approx(position):
			return creep
	return null
