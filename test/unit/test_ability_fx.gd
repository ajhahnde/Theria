extends GutTest
## The cast-FX log the simulation leaves for the renderer. A resolved cast appends one
## entry to `SimState.fx_events` carrying enough geometry to draw it — origin, landing
## point, area radius, and the cast's kind/effect/status — and `step` clears the log at the
## top of every tick, so a flash draws exactly once. The log is presentation-only: it
## never feeds back into the simulation and never crosses the wire. Headless, deterministic.

const SPIRIT_BOLT_ID := 1  # wildkin human SKILLSHOT, range 600 / radius 60
const MEND_ID := 2  # wildkin human SELF heal
const WEB_NEST_ID := 54  # spider animal GROUND stun, range 340 / radius 220


func _hero(sim: SimCore, kit_id: String, pos: Vector2) -> int:
	var id := sim.add_hero(0, pos, 300.0)
	sim.equip_kit(id, kit_id)
	return id


func test_a_skillshot_cast_records_a_beam_to_its_landing() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	var spec := AbilityData.spec(SPIRIT_BOLT_ID)
	var cmd := InputCommand.new()
	cmd.target_point = Vector2(100.0, 0.0)  # aim +x — the bolt flies the full range along it
	AbilityExecutor.execute(sim.state, sim.state.get_entity(id), spec, cmd)
	assert_eq(sim.state.fx_events.size(), 1, "the cast is recorded once")
	var fx: Dictionary = sim.state.fx_events[0]
	assert_eq(fx["kind"], AbilitySpec.TARGET_SKILLSHOT, "drawn as a skillshot beam")
	assert_eq(fx["effect"], AbilitySpec.EFFECT_DAMAGE)
	assert_eq(fx["origin"], Vector2.ZERO, "from the caster")
	assert_eq(fx["point"], Vector2(600.0, 0.0), "to the skillshot's full-range landing")


func test_a_ground_stun_cast_records_its_zone_at_true_radius() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "spider", Vector2.ZERO)
	var spec := AbilityData.spec(WEB_NEST_ID)
	var cmd := InputCommand.new()
	cmd.target_point = Vector2(300.0, 0.0)  # inside the 340 range, so it lands on the point
	AbilityExecutor.execute(sim.state, sim.state.get_entity(id), spec, cmd)
	var fx: Dictionary = sim.state.fx_events[0]
	assert_eq(fx["kind"], AbilitySpec.TARGET_GROUND, "drawn as a ground area")
	assert_eq(fx["status"], AbilitySpec.STATUS_STUN, "carries its stun so it reads as control")
	assert_eq(fx["radius"], spec.radius, "the zone is drawn at the ability's true radius")
	assert_eq(fx["point"], Vector2(300.0, 0.0), "centred where the area landed")


func test_a_self_cast_records_a_pulse_on_the_caster() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2(50.0, 0.0))
	var spec := AbilityData.spec(MEND_ID)
	AbilityExecutor.execute(sim.state, sim.state.get_entity(id), spec, InputCommand.new())
	var fx: Dictionary = sim.state.fx_events[0]
	assert_eq(fx["kind"], AbilitySpec.TARGET_SELF, "drawn as a pulse, not a beam")
	assert_eq(fx["effect"], AbilitySpec.EFFECT_HEAL)
	assert_eq(fx["point"], Vector2(50.0, 0.0), "on the caster itself")


func test_step_clears_the_previous_tick_fx_so_a_flash_draws_once() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	var cmd := InputCommand.new()
	cmd.ability_slot = 0  # Spirit Bolt
	cmd.target_point = Vector2(100.0, 0.0)
	sim.step({id: cmd})
	assert_eq(sim.state.fx_events.size(), 1, "the cast tick records its flash")
	sim.step({})  # a tick with no cast
	assert_eq(sim.state.fx_events.size(), 0, "the next tick clears it, so the flash draws once")
