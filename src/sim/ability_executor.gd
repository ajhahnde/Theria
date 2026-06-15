class_name AbilityExecutor
extends RefCounted
## Resolves and applies one ability cast against the world. Pure and engine-free,
## exactly like the simulation core it runs inside: given the world, a caster, the
## ability's spec, and the cast intent, it picks the targets and applies the effect
## deterministically — in insertion order, with integer damage — so the result is a
## function of state and input alone and replays identically.
##
## `can_cast` is the gate (form, resource, cooldown); `execute` performs the cast
## and books the cost. SimCore's ability step calls them in that order. Effects
## that reduce hp leave the kill to the core's death-resolution pass, so an ability
## and an auto-attack that both finish a unit this tick kill it once.

## Whether `caster` may cast `spec` this tick: the caster must not be stunned, the spec
## must belong to the caster's active form, the caster must hold enough resource, and the
## ability must be off cooldown. Reads only — the decision never mutates the world. Both
## the player's casts and the bot's gate through here, so a stunned hero of either kind is
## silenced by the same check.
static func can_cast(caster: SimEntity, spec: AbilitySpec) -> bool:
	if caster.is_stunned():
		return false
	if spec.form != caster.form:
		return false
	if caster.resource < spec.cost:
		return false
	if caster.ability_cooldowns.get(spec.id, 0) > 0:
		return false
	return true


## Performs the cast: applies the effect, puts the ability on cooldown, and spends
## its resource. Assumes `can_cast` already passed (SimCore gates on it), so the
## resource never goes negative. `command` carries the aim — the target point for an
## aimed ability, the target id for a unit-locked one.
static func execute(
	state: SimState, caster: SimEntity, spec: AbilitySpec, command: InputCommand
) -> void:
	match spec.effect:
		AbilitySpec.EFFECT_TRANSFORM:
			_transform(caster)
		AbilitySpec.EFFECT_HEAL:
			caster.hp = mini(caster.max_hp, caster.hp + spec.power)
		AbilitySpec.EFFECT_DAMAGE:
			for target in _targets(state, caster, spec, command):
				target.hp -= spec.power
				if spec.status != AbilitySpec.STATUS_NONE:
					_apply_status(target, spec)
	caster.ability_cooldowns[spec.id] = spec.cooldown_ticks
	caster.resource -= spec.cost
	_record_fx(state, caster, spec, command)


## Notes the cast on the state's transient FX log for the renderer — origin, landing
## point, area radius, and the cast's kind/effect/status, enough to draw a skillshot
## line or an area flash. A pure presentation side effect: the log never feeds back into
## the simulation and never crosses the wire, so recording it keeps the cast deterministic.
static func _record_fx(
	state: SimState, caster: SimEntity, spec: AbilitySpec, command: InputCommand
) -> void:
	state.fx_events.append(
		{
			"kind": spec.target_kind,
			"effect": spec.effect,
			"status": spec.status,
			"origin": caster.position,
			"point": _fx_point(state, caster, spec, command),
			"radius": spec.radius,
		}
	)


## Where a cast's FX is centred: the landing point for an aimed ability, the locked
## enemy's position for a unit-targeted one (the caster's own spot if that enemy is gone),
## and the caster for a self-cast. Mirrors `_targets`/`_landing_point` so the flash sits
## where the ability actually resolved.
static func _fx_point(
	state: SimState, caster: SimEntity, spec: AbilitySpec, command: InputCommand
) -> Vector2:
	match spec.target_kind:
		AbilitySpec.TARGET_SKILLSHOT, AbilitySpec.TARGET_GROUND:
			return _landing_point(caster, spec, command)
		AbilitySpec.TARGET_UNIT:
			var t: SimEntity = state.get_entity(command.target_id)
			return t.position if t != null else caster.position
	return caster.position


## Lays the spec's lingering status on one struck target. One instance per kind: a
## re-application overwrites any active status of the same kind, so it refreshes (the
## latest cast wins) rather than stacking — bounded and deterministic. A DOT clamps its
## interval to at least one tick and starts its damage counter fresh; a SLOW carries
## only its percent; a STUN carries only its duration (its power and interval go unused).
## The duration always starts over.
static func _apply_status(target: SimEntity, spec: AbilitySpec) -> void:
	target.statuses[spec.status] = {
		"power": spec.status_power,
		"remaining": spec.status_duration,
		"interval": maxi(1, spec.status_interval),
		"counter": 0,
	}


## Swaps the caster to its other form and to that form's resource pool: max and
## regen switch, the current pool carries over clamped to the new max, and the regen
## counter restarts. Ability cooldowns are keyed by ability id, so they persist
## untouched across the swap.
static func _transform(caster: SimEntity) -> void:
	var to_form := 1 - caster.form
	caster.form = to_form
	caster.resource_max = caster.form_resource_max[to_form]
	caster.resource_regen_ticks = caster.form_resource_regen[to_form]
	caster.resource = mini(caster.resource, caster.resource_max)
	caster.resource_regen_counter = 0


## The enemies a damaging ability strikes, by its targeting mode. SELF deals no
## outward damage (returns nothing); UNIT returns its one locked enemy when valid
## and in range; an aimed ability returns every enemy inside the area at its landing
## point. Allies and non-combat entities (max_hp 0) are never struck.
static func _targets(
	state: SimState, caster: SimEntity, spec: AbilitySpec, command: InputCommand
) -> Array[SimEntity]:
	var hits: Array[SimEntity] = []
	match spec.target_kind:
		AbilitySpec.TARGET_UNIT:
			var t: SimEntity = state.get_entity(command.target_id)
			if (
				t != null
				and t.max_hp > 0
				and t.team != caster.team
				and caster.position.distance_to(t.position) <= spec.range
			):
				hits.append(t)
		AbilitySpec.TARGET_SKILLSHOT, AbilitySpec.TARGET_GROUND:
			hits = _enemies_in_area(state, caster, _landing_point(caster, spec, command), spec.radius)
	return hits


## Where an aimed ability lands. A skillshot flies the full range along the aim
## direction (it travels through the cursor — dodgeable); a ground-target lands on
## the chosen point, pulled in to the maximum range. A zero-length aim lands on the
## caster.
static func _landing_point(caster: SimEntity, spec: AbilitySpec, command: InputCommand) -> Vector2:
	var to_aim := command.target_point - caster.position
	var dist := to_aim.length()
	if dist <= 0.0:
		return caster.position
	var dir := to_aim / dist
	if spec.target_kind == AbilitySpec.TARGET_SKILLSHOT:
		return caster.position + dir * spec.range
	return caster.position + dir * minf(spec.range, dist)


## The id of the living enemy nearest `point` — a unit-targeted ability's target
## acquisition for a cursor or click, picked by the caster's driver and validated by
## `execute` against the ability's range. 0 when the caster's enemies hold no living
## unit. Pure: a function of the world, the caster's team, and the point, so a bot
## and the client pick the same lock.
static func pick_unit_target(state: SimState, caster_team: int, point: Vector2) -> int:
	var best_id := 0
	var best_dist := INF
	for id in state.entities:
		var e: SimEntity = state.entities[id]
		if e.team == caster_team or e.max_hp <= 0:
			continue
		var d := point.distance_to(e.position)
		if d < best_dist:
			best_dist = d
			best_id = id
	return best_id


## Every living enemy of `caster` within `radius` of `center`, in deterministic
## insertion order.
static func _enemies_in_area(
	state: SimState, caster: SimEntity, center: Vector2, radius: float
) -> Array[SimEntity]:
	var hits: Array[SimEntity] = []
	for id in state.entities:
		var e: SimEntity = state.entities[id]
		if e.team == caster.team or e.max_hp <= 0:
			continue
		if center.distance_to(e.position) <= radius:
			hits.append(e)
	return hits
