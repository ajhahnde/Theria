extends GutTest
## Deterministic checks on the lingering-status layer — the venom damage-over-time and
## the web movement slow that a striking ability leaves on what it hits. These run
## headless against the same step function the client drives, with creep waves off so
## only the status under test changes the world. The status tuning is built by value
## here so a test never leans on the catalog's balance numbers.


func _sim() -> SimCore:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	return sim


## A caster whose auto-attack is silenced, so only the cast status touches the target.
func _silent_caster(sim: SimCore) -> int:
	var id := sim.add_hero(0, Vector2.ZERO, 320.0)
	sim.state.get_entity(id).attack_damage = 0
	return id


## A bare damaging UNIT spec that deals no instant hit and carries only the given
## status — so a test observes the lingering effect in isolation.
func _status_spec(status: int, power: int, duration: int, interval: int) -> AbilitySpec:
	return AbilitySpec.from_dict(
		{
			"id": 9001,
			"target_kind": AbilitySpec.TARGET_UNIT,
			"range": 1000.0,
			"effect": AbilitySpec.EFFECT_DAMAGE,
			"power": 0,
			"status": status,
			"status_power": power,
			"status_duration": duration,
			"status_interval": interval,
		}
	)


## Casts `spec` from caster onto a locked unit target, straight through the executor.
func _cast_at(sim: SimCore, caster_id: int, spec: AbilitySpec, target_id: int) -> void:
	var cmd := InputCommand.new()
	cmd.target_id = target_id
	AbilityExecutor.execute(sim.state, sim.state.get_entity(caster_id), spec, cmd)


# --- Venom: damage over time -----------------------------------------------


func test_dot_bites_each_interval_then_expires() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	# 10 hp every 5 ticks for 20 ticks: bites at ticks 5, 10, 15, 20 -> 40 total.
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_DOT, 10, 20, 5), enemy)
	assert_eq(sim.state.get_entity(enemy).hp, 600, "the zero-power strike itself deals nothing")
	assert_true(
		sim.state.get_entity(enemy).statuses.has(AbilitySpec.STATUS_DOT), "but it leaves venom"
	)
	for _i in 4:
		sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 600, "no damage before the first interval elapses")
	sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 590, "the first bite lands on the interval")
	for _i in 15:
		sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 560, "four bites over the duration: 40 total")
	assert_false(
		sim.state.get_entity(enemy).statuses.has(AbilitySpec.STATUS_DOT),
		"and the venom expires when its duration runs out",
	)
	for _i in 10:
		sim.step({})
	assert_eq(sim.state.get_entity(enemy).hp, 560, "an expired venom deals nothing more")


func test_a_lethal_dot_kills_through_the_death_pass() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 5)  # 5 hp
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_DOT, 10, 20, 1), enemy)
	sim.step({})  # a 10-hp bite against 5 hp
	assert_null(sim.state.get_entity(enemy), "a lethal bite kills, resolved in the death pass")


# --- Web: movement slow -----------------------------------------------------


func test_slow_scales_move_speed_then_lifts() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var mover := sim.add_entity(1, Vector2.ZERO, 600.0, 600)  # base speed 600
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_SLOW, 50, 10, 0), mover)
	assert_eq(sim.state.get_entity(mover).current_move_speed(), 300.0, "a 50% slow halves speed")
	var go := InputCommand.new()
	go.move_dir = Vector2(0.0, 1.0)
	sim.step({mover: go})
	# Slowed: 300 * (1/60) = 5 units, not the unslowed 10.
	assert_almost_eq(sim.state.get_entity(mover).position.y, 5.0, 0.01, "it crawls half as far")
	for _i in 10:
		sim.step({})
	assert_false(
		sim.state.get_entity(mover).statuses.has(AbilitySpec.STATUS_SLOW), "the slow lifts"
	)
	assert_eq(sim.state.get_entity(mover).current_move_speed(), 600.0, "and full speed returns")


# --- Stun: a hard lock ------------------------------------------------------


func test_stun_freezes_movement_then_lifts() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var mover := sim.add_entity(1, Vector2(100.0, 0.0), 600.0, 600)  # would move 10 a tick
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_STUN, 0, 5, 0), mover)
	assert_eq(sim.state.get_entity(mover).current_move_speed(), 0.0, "a stun zeroes move speed")
	var go := InputCommand.new()
	go.move_dir = Vector2(0.0, 1.0)
	sim.step({mover: go})
	assert_almost_eq(
		sim.state.get_entity(mover).position.y, 0.0, 0.01, "a stunned unit holds its ground"
	)
	for _i in 5:
		sim.step({mover: go})
	var freed := sim.state.get_entity(mover)
	assert_false(
		freed.statuses.has(AbilitySpec.STATUS_STUN), "the stun lifts when its duration runs out"
	)
	assert_eq(freed.current_move_speed(), 600.0, "and full move speed returns")
	assert_true(freed.position.y > 0.0, "so the unit moves again once freed")


func test_stun_blocks_casting() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var victim := sim.add_hero(1, Vector2(100.0, 0.0), 320.0)
	var ready := AbilitySpec.from_dict({})  # human form, free, off cooldown: castable by default
	assert_true(
		AbilityExecutor.can_cast(sim.state.get_entity(victim), ready),
		"an un-stunned hero can cast a ready, affordable ability",
	)
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_STUN, 0, 5, 0), victim)
	assert_false(
		AbilityExecutor.can_cast(sim.state.get_entity(victim), ready),
		"but a stunned hero cannot cast at all",
	)
	for _i in 5:
		sim.step({})
	assert_true(
		AbilityExecutor.can_cast(sim.state.get_entity(victim), ready),
		"and casting returns once the stun lifts",
	)


func test_stun_blocks_auto_attack() -> void:
	var sim := _sim()
	var attacker := sim.add_hero(0, Vector2.ZERO, 0.0)  # 60 damage, range 250, cooldown 36
	var dummy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)  # in range, takes the hit
	# A team-1 source to lay the stun on the team-0 attacker; silenced so only the stun,
	# not its own attack, touches the world.
	var stun_src := sim.add_hero(1, Vector2(120.0, 0.0), 0.0)
	sim.state.get_entity(stun_src).attack_damage = 0
	_cast_at(sim, stun_src, _status_spec(AbilitySpec.STATUS_STUN, 0, 5, 0), attacker)
	for _i in 4:
		sim.step({})
	assert_eq(sim.state.get_entity(dummy).hp, 600, "a stunned attacker lands no auto-attack")
	sim.step({})  # the stun lifts this tick and the attacker, off cooldown, strikes
	assert_eq(sim.state.get_entity(dummy).hp, 540, "and it attacks again once the stun lifts")


# --- Stacking + determinism -------------------------------------------------


func test_reapplying_a_status_refreshes_rather_than_stacks() -> void:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	var spec := _status_spec(AbilitySpec.STATUS_DOT, 10, 20, 5)
	_cast_at(sim, caster, spec, enemy)
	sim.step({})
	sim.step({})  # age it two ticks: counter 2, remaining 18
	_cast_at(sim, caster, spec, enemy)  # recast
	var e := sim.state.get_entity(enemy)
	assert_eq(e.statuses.size(), 1, "a re-applied status does not stack a second instance")
	assert_eq(e.statuses[AbilitySpec.STATUS_DOT]["remaining"], 20, "it refreshes the duration")
	assert_eq(e.statuses[AbilitySpec.STATUS_DOT]["counter"], 0, "and restarts the interval")


func test_a_status_run_replays_identically() -> void:
	var a := _run()
	var b := _run()
	assert_eq(a, b, "the status layer must be a pure function of state + input")


## A scripted run: a venom DOT and a web slow laid on one enemy, then a fixed window
## stepped out. Returns a comparable digest so two runs check field-for-field.
func _run() -> Array:
	var sim := _sim()
	var caster := _silent_caster(sim)
	var enemy := sim.add_entity(1, Vector2(100.0, 0.0), 0.0, 600)
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_DOT, 7, 30, 6), enemy)
	_cast_at(sim, caster, _status_spec(AbilitySpec.STATUS_SLOW, 40, 15, 0), enemy)
	for _i in 40:
		sim.step({})
	var rows: Array = []
	for id in sim.state.entities:
		var en: SimEntity = sim.state.entities[id]
		rows.append([id, en.hp, en.position.round()])
	return rows


# --- Catalog wiring ---------------------------------------------------------


func test_the_catalog_wires_venom_to_dot_and_web_to_slow() -> void:
	var venom := AbilityData.spec(44)  # Snake: Venom Coil
	assert_eq(venom.status, AbilitySpec.STATUS_DOT, "Venom Coil carries a venom DOT")
	assert_true(venom.status_power > 0, "with real per-interval damage")
	assert_true(venom.status_duration > 0 and venom.status_interval > 0, "and a real cadence")
	var web := AbilityData.spec(50)  # Spider: Web Snare
	assert_eq(web.status, AbilitySpec.STATUS_SLOW, "Web Snare carries a web slow")
	assert_true(web.status_power > 0 and web.status_duration > 0, "with a real slow")
	var burst := AbilityData.spec(14)  # Solane: Maul -- pure burst
	assert_eq(burst.status, AbilitySpec.STATUS_NONE, "a Solane strike leaves no status")


func test_the_catalog_wires_web_nest_to_a_stun() -> void:
	var nest := AbilityData.spec(54)  # Spider: Web Nest
	assert_eq(nest.status, AbilitySpec.STATUS_STUN, "Web Nest now carries a hard stun")
	assert_true(nest.status_duration > 0, "with a real lock duration")
	var snare := AbilityData.spec(50)  # Spider: Web Snare -- still a slow
	assert_eq(snare.status, AbilitySpec.STATUS_SLOW, "the Spider keeps its Web Snare slow")
