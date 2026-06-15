extends GutTest
## Data checks on the Solane roster — the first tribe's three hero kits (Lion, Cheetah,
## Hyena). The ability executor itself is proven by test_ability.gd against the wildkin
## kit; these tests prove the *content* is wired correctly: the right ability sits in
## the right slot and form, the tuned numbers land, the transforms flip, and the three
## resource economies are tiered as designed. Headless and deterministic, creep waves
## off, so only the ability under test changes the world.

const SOLANE := ["lion", "cheetah", "hyena"]


func _solane(sim: SimCore, kit_id: String, team: int, pos: Vector2) -> int:
	var id := sim.add_hero(team, pos, 320.0)
	sim.equip_kit(id, kit_id)
	return id


## Equips a Solane hero and transforms it to its animal form with a real cast (human
## slot 3 = that hero's beast-form ability), so the animal-kit tests start from the
## form the transform actually produces.
func _solane_animal(sim: SimCore, kit_id: String, team: int, pos: Vector2) -> int:
	var id := _solane(sim, kit_id, team, pos)
	var beast := InputCommand.new()
	beast.ability_slot = 3
	sim.step({id: beast})
	return id


# --- Roster shape -----------------------------------------------------------


func test_solane_kits_are_well_formed() -> void:
	for kit_id in SOLANE:
		var sim := SimCore.new()
		sim.spawn_creeps = false
		var id := _solane(sim, kit_id, 0, Vector2.ZERO)
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


func test_solane_kits_use_disjoint_ability_ids() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var seen := {}
	var total := 0
	for kit_id in SOLANE:
		var id := _solane(sim, kit_id, 0, Vector2.ZERO)
		var kit: Dictionary = sim.state.get_entity(id).kit
		for form in kit:
			for slot in kit[form]:
				seen[kit[form][slot]] = true
				total += 1
	assert_eq(seen.size(), total, "no two Solane kits share an ability id (a copy-paste guard)")


# --- Each hero's signature ability lands its tuning --------------------------


func test_lion_maul_is_the_heaviest_single_hit() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _solane_animal(sim, "lion", 0, Vector2.ZERO)
	sim.state.get_entity(id).attack_damage = 0  # isolate Maul from the auto-attack
	var enemy := sim.add_entity(1, Vector2(180.0, 0.0), 0.0, 600)  # inside Maul's 190 range
	var cast := InputCommand.new()
	cast.ability_slot = 2  # animal E = Maul
	cast.target_id = enemy
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(enemy).hp, 440, "Maul deals its 160 to the locked target")


func test_cheetah_spear_throw_reaches_the_longest() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _solane(sim, "cheetah", 0, Vector2.ZERO)
	var far := sim.add_entity(1, Vector2(750.0, 0.0), 0.0, 600)  # at Spear Throw's full 750 range
	var cast := InputCommand.new()
	cast.ability_slot = 0  # human Q = Spear Throw
	cast.target_point = Vector2(100.0, 0.0)  # any +x point: the skillshot flies the full range
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(far).hp, 510, "Spear Throw clips an enemy 750 away")
	assert_eq(sim.state.get_entity(id).resource, 60, "and spends its 20 from the lean 80 pool")


func test_hyena_bone_hex_zones_a_wide_area() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _solane(sim, "hyena", 0, Vector2.ZERO)
	# Bone-Hex: GROUND, range 600, radius 190. Land it at (600,0).
	var inside := sim.add_entity(1, Vector2(600.0, 150.0), 0.0, 600)  # 150 from centre -> hit
	var outside := sim.add_entity(1, Vector2(600.0, 300.0), 0.0, 600)  # 300 from centre -> spared
	var cast := InputCommand.new()
	cast.ability_slot = 0  # human Q = Bone-Hex
	cast.target_point = Vector2(600.0, 0.0)
	sim.step({id: cast})
	assert_eq(sim.state.get_entity(inside).hp, 545, "an enemy in the wide zone takes Bone-Hex's 55")
	assert_eq(sim.state.get_entity(outside).hp, 600, "an enemy beyond its radius is spared")


# --- Forms and economy ------------------------------------------------------


func test_each_solane_hero_transforms_to_its_beast() -> void:
	for kit_id in SOLANE:
		var sim := SimCore.new()
		sim.spawn_creeps = false
		var id := _solane(sim, kit_id, 0, Vector2.ZERO)
		var beast := InputCommand.new()
		beast.ability_slot = 3
		sim.step({id: beast})
		assert_eq(
			sim.state.get_entity(id).form,
			AbilitySpec.FORM_ANIMAL,
			"%s flips to its animal form on the slot-3 transform" % kit_id,
		)


func test_solane_resource_economies_are_tiered() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var lion := sim.state.get_entity(_solane(sim, "lion", 0, Vector2(0, 0)))
	var cheetah := sim.state.get_entity(_solane(sim, "cheetah", 0, Vector2(50, 0)))
	var hyena := sim.state.get_entity(_solane(sim, "hyena", 0, Vector2(100, 0)))
	assert_eq(cheetah.resource_max, 80, "the cheetah runs the leanest pool")
	assert_eq(hyena.resource_max, 100, "the hyena sits at the baseline")
	assert_eq(lion.resource_max, 120, "the lion carries the deepest pool")
	assert_true(
		cheetah.resource_regen_ticks < hyena.resource_regen_ticks,
		"and the cheetah's lean pool refills fastest",
	)
