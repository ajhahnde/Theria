extends GutTest
## Behaviour checks on the bot's ability casting. The bot walks toward the nearest
## enemy (the walking-skeleton behaviour) and, once it is a kitted hero, layers a
## cast onto that intent: it shifts form to keep a hit (and its heal) in reach, then
## self-heals when hurt, otherwise fires the first damaging ability of its active
## form that can actually reach the target. These pin the selection order, the
## per-targeting-mode reach gate, the form-shift policy, plus one end-to-end check
## that a chosen cast lands in the sim. Headless and deterministic, creep waves off.

const WILDKIN_SPIRIT_BOLT_SLOT := 0  # human SKILLSHOT, range 600 / radius 60
const WILDKIN_MEND_SLOT := 1  # human HEAL
const TRANSFORM_SLOT := 3  # the R slot holds the form swap in every kit
const LION_HEAL_ID := 11  # Mane Guard, the Lion's human-form heal


func _bot() -> BotController:
	return BotController.new()


func _hero(sim: SimCore, kit_id: String, pos: Vector2) -> int:
	var id := sim.add_hero(0, pos, 300.0)
	sim.equip_kit(id, kit_id)
	return id


## Steps the hero into its animal form by casting the form-swap slot, so a test can
## start from the animal kit. No enemy need be present — a transform is self-cast.
func _to_animal(sim: SimCore, hero_id: int) -> void:
	var shift := InputCommand.new()
	shift.ability_slot = TRANSFORM_SLOT
	sim.step({hero_id: shift})


# --- The is-a-kitted-hero gate ----------------------------------------------


func test_a_bot_without_a_kit_only_moves() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var mover := sim.add_hero(0, Vector2.ZERO, 300.0)  # never equipped -> not a caster
	sim.add_entity(1, Vector2(400.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, mover)
	assert_eq(command.ability_slot, -1, "a kit-less hero never casts")
	assert_ne(command.move_dir, Vector2.ZERO, "but it still advances on the enemy")


# --- Selection: which slot, by reach and effect -----------------------------


func test_bot_fires_a_skillshot_at_an_enemy_in_its_band() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)  # at the skillshot's exact range
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, WILDKIN_SPIRIT_BOLT_SLOT, "it casts the reachable skillshot")
	assert_eq(command.target_point, Vector2(600.0, 0.0), "aimed straight at the enemy")


func test_bot_holds_fire_when_no_ability_can_reach() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	# Far outside the skillshot's [range-radius, range+radius] band: a cast would
	# strike empty air, so the bot must not spend it.
	sim.add_entity(1, Vector2(1200.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, -1, "a full-health bot out of reach casts nothing")
	assert_ne(command.move_dir, Vector2.ZERO, "it closes the distance instead")


func test_bot_picks_a_ground_ability_that_can_reach() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "hyena", Vector2.ZERO)  # human slot 0 = Bone-Hex, GROUND
	sim.add_entity(1, Vector2(400.0, 0.0), 0.0, 600)  # inside range + radius
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "the ground area is cast on a reachable enemy")
	assert_eq(command.target_point, Vector2(400.0, 0.0), "dropped on the target")


func test_a_unit_ability_locks_the_target() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "cheetah", Vector2.ZERO)
	# Shift to the animal kit, whose slot 0 (Hamstring) is unit-targeted.
	var beast := InputCommand.new()
	beast.ability_slot = 3
	sim.step({id: beast})
	var enemy := sim.add_entity(1, Vector2(200.0, 0.0), 0.0, 600)  # inside Hamstring's 280
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "the unit ability is selected")
	assert_eq(command.target_id, enemy, "and locked onto the nearest enemy")


func test_a_hurt_bot_heals_before_it_attacks() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.state.get_entity(id).hp = 100  # well under the 60% heal threshold of 600
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)  # a damage target is also in reach
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, WILDKIN_MEND_SLOT, "survival comes first: it heals, not pokes")


# --- Stance: shifting form to keep a hit (and a heal) in reach ---------------


func test_bot_transforms_to_engage_when_only_the_other_form_reaches() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "lion", Vector2.ZERO)  # human slot 0 = Sunfire Lash, a skillshot
	# Inside the skillshot's dead zone (its band is around the 450 range) but well
	# within the animal kit's reach: the human poke would whiff, so the bot shifts.
	sim.add_entity(1, Vector2(150.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, TRANSFORM_SLOT, "it transforms instead of whiffing the poke")
	assert_eq(
		sim.state.get_entity(id).form, AbilitySpec.FORM_HUMAN, "the shift is queued, not yet applied"
	)


func test_bot_does_not_transform_while_its_current_form_can_hit() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "lion", Vector2.ZERO)
	# At the skillshot's exact range the human poke lands; the animal kit reaches
	# too, but a form that can already hit does not give up its turn to shift.
	sim.add_entity(1, Vector2(450.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "it pokes with the reachable human ability, no transform")


func test_bot_transforms_back_when_the_enemy_outruns_the_animal_kit() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "cheetah", Vector2.ZERO)
	_to_animal(sim, id)  # the animal kit reaches only to 280 (Hamstring / Killing Blow)
	# Far outside the animal kit but on the human Spear Throw's 750 range: shift back.
	sim.add_entity(1, Vector2(750.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, TRANSFORM_SLOT, "it shifts back toward the human poke")
	assert_eq(
		sim.state.get_entity(id).form, AbilitySpec.FORM_ANIMAL, "still animal until the cast resolves"
	)


func test_a_hurt_bot_in_animal_form_retreats_to_the_human_heal() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "lion", Vector2.ZERO)
	_to_animal(sim, id)
	sim.state.get_entity(id).hp = 100  # under the 60% heal threshold of 600
	sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)  # within the animal kit's reach
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, TRANSFORM_SLOT, "it abandons the brawl to reach its heal")


func test_a_hurt_bot_stays_in_animal_form_when_the_heal_is_on_cooldown() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "lion", Vector2.ZERO)
	_to_animal(sim, id)
	var bot := sim.state.get_entity(id)
	bot.hp = 100
	bot.ability_cooldowns[LION_HEAL_ID] = 50  # Mane Guard not ready: no point flipping for it
	sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "with no heal to reach it fights on with the animal kit")


# --- End to end: the chosen cast lands --------------------------------------


func test_a_bot_cast_lands_in_the_sim() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.state.get_entity(id).move_speed = 0.0  # hold position so the cast geometry is exact
	# At the skillshot's range (600), and beyond the 250 auto-attack range, so only the cast lands.
	var enemy := sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	sim.step({id: _bot().decide(sim.state, id)})
	assert_eq(sim.state.get_entity(enemy).hp, 520, "Spirit Bolt's 80 lands on the enemy")
	assert_eq(sim.state.get_entity(id).resource, 80, "and its 20 cost is booked")
