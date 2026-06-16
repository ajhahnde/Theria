extends GutTest
## Deterministic checks on the hero ability layer — targeting, the per-form
## resource, cooldowns, and the shapeshift transform. These run headless against the
## exact step function the live client (later) drives, with creep waves off so only
## the ability under test changes the world.


func _hero(sim: SimCore, team: int, pos: Vector2) -> int:
	var id := sim.add_hero(team, pos, 320.0)
	sim.equip_kit(id, "wildkin")
	return id


## Equips a wildkin hero and transforms it to its animal form with a real Beast Form
## cast, so the animal-kit tests start from the form the transform actually produces.
func _animal_hero(sim: SimCore, team: int, pos: Vector2) -> int:
	var id := _hero(sim, team, pos)
	var beast := InputCommand.new()
	beast.ability_slot = 3  # human slot 3 = Beast Form
	sim.step({id: beast})
	return id


# --- Equip + form -----------------------------------------------------------


func test_equip_kit_makes_a_human_caster_with_a_full_pool() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var h := sim.state.get_entity(id)
	assert_true(h.is_hero, "an equipped hero is an ability caster")
	assert_eq(h.form, AbilitySpec.FORM_HUMAN, "a freshly equipped hero starts human")
	assert_eq(h.resource, 100, "and with its human pool full")
	assert_eq(h.resource_max, 100)
	assert_eq(h.kit[AbilitySpec.FORM_HUMAN][0], 1, "Spirit Bolt sits in the human Q slot")


# --- Targeting: skillshot, ground, unit -------------------------------------


func test_skillshot_strikes_an_enemy_at_its_landing_point() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	# Range 600 along +x; the bolt flies the full range and clips an enemy there.
	var enemy := sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	var cast := InputCommand.new()
	cast.ability_slot = 0
	cast.target_point = Vector2(100.0, 0.0)  # any point along +x: a skillshot flies through it
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(enemy).hp, 520, "Spirit Bolt deals its power at the landing point")
	assert_eq(sim.state.get_entity(id).resource, 80, "and the cast spends its resource")


func test_skillshot_misses_when_aimed_away() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var enemy := sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	var cast := InputCommand.new()
	cast.ability_slot = 0
	cast.target_point = Vector2(0.0, 100.0)  # aimed up +y: lands at (0,600), nowhere near the enemy
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(enemy).hp, 600, "a bolt aimed away does not hit")


func test_ground_area_strikes_every_enemy_in_its_radius() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _animal_hero(sim, 0, Vector2.ZERO)
	# Pounce: GROUND, range 400, radius 150. Land it at (400,0).
	var inside := sim.add_entity(1, Vector2(400.0, 100.0), 0.0, 600)  # 100 from centre -> hit
	var outside := sim.add_entity(1, Vector2(400.0, 300.0), 0.0, 600)  # 300 from centre -> spared
	var cast := InputCommand.new()
	cast.ability_slot = 0  # animal Q = Pounce
	cast.target_point = Vector2(400.0, 0.0)
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(inside).hp, 540, "an enemy inside the area is struck")
	assert_eq(sim.state.get_entity(outside).hp, 600, "an enemy outside the radius is spared")


func test_unit_ability_strikes_its_locked_target() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _animal_hero(sim, 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0  # isolate Rend from the auto-attack (same range band)
	var enemy := sim.add_entity(1, Vector2(150.0, 0.0), 0.0, 600)  # inside Rend's 200 range
	var cast := InputCommand.new()
	cast.ability_slot = 2  # animal E = Rend
	cast.target_id = enemy
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(enemy).hp, 480, "Rend deals its power to the locked target")


func test_unit_ability_whiffs_on_an_out_of_range_target() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _animal_hero(sim, 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0
	var enemy := sim.add_entity(1, Vector2(300.0, 0.0), 0.0, 600)  # beyond Rend's 200 range
	var cast := InputCommand.new()
	cast.ability_slot = 2
	cast.target_id = enemy
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(enemy).hp, 600, "an out-of-range unit cast lands no damage")
	assert_eq(sim.state.get_entity(id).resource, 70, "but the whiffed cast still books its cost")


# --- Unit target acquisition (the driver's cursor pick) ---------------------


func test_pick_unit_target_returns_the_nearest_enemy() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var near := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	sim.add_entity(1, Vector2(500.0, 0.0), 0.0, 600)
	var picked := AbilityExecutor.pick_unit_target(sim.state, 0, Vector2(120.0, 0.0))
	assert_eq(picked, near, "the enemy nearest the point is acquired")


func test_pick_unit_target_ignores_allies_and_empties() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	sim.add_entity(0, Vector2(100.0, 0.0), 0.0, 600)  # an ally near the point
	assert_eq(
		AbilityExecutor.pick_unit_target(sim.state, 0, Vector2(100.0, 0.0)),
		0,
		"no enemy in the world acquires nothing, never an ally",
	)


# --- Effects: heal, transform -----------------------------------------------


func test_self_heal_restores_hp_clamped_to_max() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var h := sim.state.get_entity(id)
	h.hp = 550  # Mend heals 100; from 550 the clamp caps the result at max_hp, not 650
	var cast := InputCommand.new()
	cast.ability_slot = 1  # human W = Mend
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(id).hp, 600, "a self-heal never overfills past max_hp")
	assert_eq(sim.state.get_entity(id).resource, 70, "Mend spends its cost")


func test_transform_swaps_form_and_keeps_cooldowns_running() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	# Put Spirit Bolt on cooldown, then transform.
	var bolt := InputCommand.new()
	bolt.ability_slot = 0
	bolt.target_point = Vector2(100.0, 0.0)
	sim.step({id: bolt})
	var beast := InputCommand.new()
	beast.ability_slot = 3  # human R = Beast Form
	sim.step({id: beast})
	var h := sim.state.get_entity(id)
	assert_eq(h.form, AbilitySpec.FORM_ANIMAL, "Beast Form swaps the hero to its animal form")
	assert_true(h.ability_cooldowns[1] > 0, "the human bolt cooldown keeps running across the swap")
	assert_eq(h.resource_max, 100, "the animal pool is active after the swap")


# --- Gates: form, resource, cooldown ----------------------------------------


func test_can_cast_gates_on_form_resource_and_cooldown() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var h := sim.state.get_entity(id)
	var bolt := AbilityData.spec(1)  # human Spirit Bolt, cost 20
	var pounce := AbilityData.spec(4)  # animal Pounce
	assert_true(AbilityExecutor.can_cast(h, bolt), "a human, full, ready hero can cast in form")
	assert_false(AbilityExecutor.can_cast(h, pounce), "an animal ability is not castable while human")
	h.resource = 10
	assert_false(AbilityExecutor.can_cast(h, bolt), "a cast is refused without enough resource")
	h.resource = 100
	h.ability_cooldowns[1] = 5
	assert_false(AbilityExecutor.can_cast(h, bolt), "a cast is refused while on cooldown")


func test_cooldown_blocks_recast_until_it_elapses() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var cast := InputCommand.new()
	cast.ability_slot = 0
	cast.target_point = Vector2(100.0, 0.0)
	sim.step({id: cast})  # cast 1: Spirit Bolt -> cooldown 30
	var h := sim.state.get_entity(id)
	assert_eq(h.ability_cooldowns[1], 30, "the ability enters its full cooldown when cast")
	sim.step({id: cast})  # a recast one tick later is refused
	assert_eq(h.ability_cooldowns[1], 29, "the cooldown ticks down and the recast is dropped")
	for _i in 29:
		sim.step({})
	assert_eq(h.ability_cooldowns[1], 0, "the cooldown reaches zero")
	sim.step({id: cast})  # now the recast lands
	assert_eq(h.ability_cooldowns[1], 30, "off cooldown, the recast lands and re-enters cooldown")


func test_resource_regenerates_on_its_interval() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	var cast := InputCommand.new()
	cast.ability_slot = 0
	cast.target_point = Vector2(100.0, 0.0)
	sim.step({id: cast})  # spend 20 -> 80
	var h := sim.state.get_entity(id)
	assert_eq(h.resource, 80, "the cast leaves the pool down by its cost")
	for _i in 12:  # regen is one point every 12 ticks
		sim.step({})
	assert_eq(h.resource, 81, "one point regenerates after the interval")
	for _i in 12:
		sim.step({})
	assert_eq(h.resource, 82, "and another after the next interval")


# --- Inert without a kit + determinism --------------------------------------


func test_an_unequipped_hero_ignores_ability_intent() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := sim.add_hero(0, Vector2.ZERO, 320.0)  # no equip_kit
	var enemy := sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	var cast := InputCommand.new()
	cast.ability_slot = 0
	cast.target_point = Vector2(100.0, 0.0)
	sim.step({id: cast})  # must not cast or crash
	assert_true(sim.state.get_entity(id).kit.is_empty(), "a bare hero carries no kit to cast from")
	assert_eq(sim.state.get_entity(enemy).hp, 600, "and its ability intent does nothing")


func test_an_ability_run_replays_identically() -> void:
	var a := _run_abilities()
	var b := _run_abilities()
	assert_eq(a, b, "the ability layer must be a pure function of state + input")


## A scripted ability sequence over a fixed window: a hero casts a bolt, transforms,
## pounces, and idles, against two enemies. Returns a deterministic digest of the
## survivors so two runs can be compared field-for-field.
func _run_abilities() -> Array:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, 0, Vector2.ZERO)
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	sim.add_entity(1, Vector2(400.0, 80.0), 0.0, 600)
	var script: Array[InputCommand] = []
	for i in 90:
		var cmd := InputCommand.new()
		if i == 0:
			cmd.ability_slot = 0  # Spirit Bolt
			cmd.target_point = Vector2(100.0, 0.0)
		elif i == 5:
			cmd.ability_slot = 3  # Beast Form
		elif i == 10:
			cmd.ability_slot = 0  # Pounce (animal)
			cmd.target_point = Vector2(400.0, 0.0)
		else:
			cmd.ability_slot = -1
		script.append(cmd)
	for cmd in script:
		sim.step({id: cmd})
	return _digest(sim.state)


## A stable, comparable digest of the world: every surviving entity's id, hp, and
## rounded position, ordered by id.
func _digest(state: SimState) -> Array:
	var ids := state.entities.keys()
	ids.sort()
	var rows: Array = []
	for id in ids:
		var e: SimEntity = state.entities[id]
		rows.append([id, e.hp, e.position.round()])
	return rows
