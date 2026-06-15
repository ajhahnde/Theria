extends GutTest
## Data checks on the Verdani roster — the second tribe's three hero kits (Snake, Spider,
## Chameleon), the jungle foil to the Solane. The executor itself is proven by
## test_ability.gd; these tests prove the *content*: the right ability sits in the right
## slot and form, the tuned numbers land, the transforms flip, the three economies are
## tiered as designed, and the Verdani ids stay clear of the Solane the squad shares the
## arena with. Headless and deterministic, creep waves off, so only the ability under
## test changes the world.

const VERDANI := ["snake", "spider", "chameleon"]
const SOLANE := ["lion", "cheetah", "hyena"]


func _verdani(sim: SimCore, kit_id: String, team: int, pos: Vector2) -> int:
	var id := sim.add_hero(team, pos, 320.0)
	sim.equip_kit(id, kit_id)
	return id


## Equips a Verdani hero and transforms it to its animal form with a real cast (human
## slot 3 = that hero's beast-form ability), so the animal-kit tests start from the form
## the transform actually produces.
func _verdani_animal(sim: SimCore, kit_id: String, team: int, pos: Vector2) -> int:
	var id := _verdani(sim, kit_id, team, pos)
	var beast := InputCommand.new()
	beast.ability_slot = 3
	sim.step({id: beast})
	return id


# --- Roster shape -----------------------------------------------------------


func test_verdani_kits_are_well_formed() -> void:
	for kit_id in VERDANI:
		var sim := SimCore.new()
		sim.spawn_creeps = false
		var id := _verdani(sim, kit_id, 0, Vector2.ZERO)
		var h := sim.state.get_entity(id)
		assert_true(h.is_hero, "%s is an ability caster once equipped" % kit_id)
		assert_eq(h.form, AbilitySpec.FORM_HUMAN, "%s starts in human form" % kit_id)
		for form in [AbilitySpec.FORM_HUMAN, AbilitySpec.FORM_ANIMAL]:
			var slots: Dictionary = h.kit[form]
			assert_true(slots.has(3), "%s form %d carries a transform in slot 3" % [kit_id, form])
			for slot in slots:
				var spec := AbilityData.spec(slots[slot])
				assert_true(AbilityData.has_ability(spec.id), "%s slot %d is a real ability" % [kit_id, slot])
				assert_eq(spec.form, form, "%s slot %d ability is in its own form" % [kit_id, slot])
				assert_eq(spec.slot, slot, "%s ability %d sits in its kit slot" % [kit_id, spec.id])
			assert_eq(
				AbilityData.spec(slots[3]).effect,
				AbilitySpec.EFFECT_TRANSFORM,
				"%s slot 3 is the transform" % kit_id,
			)


func test_verdani_kits_use_disjoint_ability_ids() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var seen := {}
	var total := 0
	for kit_id in VERDANI:
		var id := _verdani(sim, kit_id, 0, Vector2.ZERO)
		var kit: Dictionary = sim.state.get_entity(id).kit
		for form in kit:
			for slot in kit[form]:
				seen[kit[form][slot]] = true
				total += 1
	assert_eq(seen.size(), total, "no two Verdani kits share an ability id (a copy-paste guard)")


func test_verdani_ids_are_clear_of_the_solane() -> void:
	# Both tribes are on the field at once in a practice match, so their catalog ids must
	# not collide — a Solane id and a Verdani id resolving to one row would cross-wire
	# the two rosters.
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var solane_ids := {}
	for kit_id in SOLANE:
		var kit: Dictionary = sim.state.get_entity(_verdani(sim, kit_id, 0, Vector2.ZERO)).kit
		for form in kit:
			for slot in kit[form]:
				solane_ids[kit[form][slot]] = true
	for kit_id in VERDANI:
		var kit: Dictionary = sim.state.get_entity(_verdani(sim, kit_id, 1, Vector2.ZERO)).kit
		for form in kit:
			for slot in kit[form]:
				var vid: int = kit[form][slot]
				assert_false(solane_ids.has(vid), "Verdani id %d is clear of the Solane" % vid)


# --- Each hero's signature ability lands its tuning --------------------------


func test_snake_fang_strike_locks_the_longest_single_target() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _verdani_animal(sim, "snake", 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0  # isolate Fang Strike from the auto-attack
	var far := sim.add_entity(1, Vector2(360.0, 0.0), 0.0, 600)  # at Fang Strike's full 360 lock
	var cast := InputCommand.new()
	cast.ability_slot = 0  # animal Q = Fang Strike
	cast.target_id = far
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(far).hp, 525, "Fang Strike locks a target 360 away for its 75")
	assert_eq(sim.state.get_entity(id).resource, 75, "and spends its cheap 15 from the 90 pool")


func test_spider_web_nest_zones_the_widest_area() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _verdani_animal(sim, "spider", 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0  # isolate Web Nest from the auto-attack
	# Web Nest: GROUND, range 340, radius 220 — the widest in either tribe. Land it at
	# (300,0) and bracket an enemy just inside the radius against one just outside.
	var inside := sim.add_entity(1, Vector2(300.0, 210.0), 0.0, 600)  # 210 from centre -> hit
	var outside := sim.add_entity(1, Vector2(300.0, 235.0), 0.0, 600)  # 235 from centre -> spared
	var cast := InputCommand.new()
	cast.ability_slot = 2  # animal E = Web Nest
	cast.target_point = Vector2(300.0, 0.0)
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(inside).hp, 545, "an enemy in the wide nest takes Web Nest's 55")
	assert_eq(sim.state.get_entity(outside).hp, 600, "an enemy beyond its 220 radius is spared")


func test_chameleon_ambush_is_the_heaviest_single_hit() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _verdani_animal(sim, "chameleon", 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0  # isolate Ambush from the auto-attack
	var enemy := sim.add_entity(1, Vector2(180.0, 0.0), 0.0, 600)  # inside Ambush's 200 range
	var cast := InputCommand.new()
	cast.ability_slot = 2  # animal E = Ambush
	cast.target_id = enemy
	sim.step({id: cast})
	assert_eq(
		sim.state.get_entity(enemy).hp, 435, "Ambush deals its 165 — the hardest hit in either tribe"
	)
	assert_eq(sim.state.get_entity(id).resource, 35, "and spends its 35 from the lean 70 pool")


# --- Forms and economy ------------------------------------------------------


func test_each_verdani_hero_transforms_to_its_beast() -> void:
	for kit_id in VERDANI:
		var sim := SimCore.new()
		sim.spawn_creeps = false
		var id := _verdani(sim, kit_id, 0, Vector2.ZERO)
		var beast := InputCommand.new()
		beast.ability_slot = 3
		sim.step({id: beast})
		assert_eq(
			sim.state.get_entity(id).form,
			AbilitySpec.FORM_ANIMAL,
			"%s flips to its animal form on the slot-3 transform" % kit_id,
		)


func test_verdani_resource_economies_are_tiered() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var snake := sim.state.get_entity(_verdani(sim, "snake", 0, Vector2(0, 0)))
	var spider := sim.state.get_entity(_verdani(sim, "spider", 0, Vector2(50, 0)))
	var chameleon := sim.state.get_entity(_verdani(sim, "chameleon", 0, Vector2(100, 0)))
	assert_eq(chameleon.resource_max, 70, "the chameleon runs the leanest pool")
	assert_eq(snake.resource_max, 90, "the snake sits between, a precise mid-tier pool")
	assert_eq(spider.resource_max, 110, "the spider carries the deepest pool")
	assert_true(
		chameleon.resource_regen_ticks < snake.resource_regen_ticks
		and snake.resource_regen_ticks < spider.resource_regen_ticks,
		"and the leaner the pool, the faster it refills",
	)
