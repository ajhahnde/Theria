class_name BotController
extends RefCounted
## Produces an InputCommand for a bot-controlled entity from the world state.
##
## v0.1 behaviour: position against the nearest enemy and — once the entity is a kitted
## hero — cast its abilities. Positioning follows the kit's stance (AbilityData.STANCE_*):
## a BRAWLER walks in, stops on contact, and shifts toward whichever form can land a hit
## (closing into its animal kit when an enemy slips inside the human poke's reach, falling
## back to the human form to poke at range or to heal when hurt); a KITER (the skirmishers)
## instead holds its ranged form and keeps the enemy inside its skillshot band — backing
## off a point-blank enemy and closing on a distant one — so it pokes hit-and-run rather
## than committing to melee. Either way it heals when hurt and otherwise fires the first
## damaging ability of its active form that can actually reach the target.
## Deterministic — a pure function of the state — so a bot match replays identically
## and feeds the same simulation core a human would, gating every cast (a transform
## included) on the very `AbilityExecutor.can_cast` the player's casts pass through.

## Stop advancing once within this many world units of the target.
const STOP_RANGE := 60.0

## The ability bar is four slots (0..3) per form; the bot scans them in order so its
## pick is deterministic by slot rather than by dictionary iteration order.
const SLOT_COUNT := 4

## Heal once health falls below this fraction of the maximum — soon enough to
## matter in a trade, but not so eager the bot tops off a scratch every tick. The
## same threshold tells the bot when to favour the human form for its heal.
const HEAL_HP_FRACTION := 0.6


func decide(state: SimState, bot_id: int) -> InputCommand:
	var command := InputCommand.new()
	var bot := state.get_entity(bot_id)
	if bot == null:
		return command
	var target := _nearest_enemy(state, bot)
	if target == null:
		return command
	if bot.is_hero and bot.stance == AbilityData.STANCE_KITE:
		_kite_move(command, bot, target)
	else:
		var offset := target.position - bot.position
		if offset.length() > STOP_RANGE:
			command.move_dir = offset.normalized()
	if bot.is_hero:
		_choose_cast(command, bot, target)
	return command


## Layers an ability cast onto the bot's command when one is worth casting this
## tick. Stance comes first: when the bot would fight better in its other form it
## transforms — gated like every cast, so a bot still on transform cooldown simply
## fights on where it is. Otherwise it self-heals when hurt and can afford one, else
## fires the first damaging ability of its active form that lands on `target`. Reads
## the same state the player's input sampler does and gates on the same cast rules,
## so a bot's casts stay pure and replayable.
func _choose_cast(command: InputCommand, bot: SimEntity, target: SimEntity) -> void:
	if _preferred_form(bot, target) != bot.form:
		var transform_slot := _castable_slot(bot, bot.form, AbilitySpec.EFFECT_TRANSFORM, target)
		if transform_slot >= 0:
			command.ability_slot = transform_slot
			return
	if _is_hurt(bot):
		var heal_slot := _castable_slot(bot, bot.form, AbilitySpec.EFFECT_HEAL, target)
		if heal_slot >= 0:
			command.ability_slot = heal_slot
			return
	var damage_slot := _castable_slot(bot, bot.form, AbilitySpec.EFFECT_DAMAGE, target)
	if damage_slot >= 0:
		command.ability_slot = damage_slot
		command.target_point = target.position
		command.target_id = target.id


## The form the bot would rather fight this target in. Survival comes first: a hurt
## bot in the animal form wants the human form's heal (the animal kits carry none),
## but only when that heal is off cooldown — cooldowns persist across a transform,
## so the bot reads it from either stance, and it never flips toward a heal still
## recharging. Otherwise it shifts on reach: to the other form when its current one
## cannot land a damaging ability but the other could — closing into the animal kit
## as an enemy slips inside the human skillshot's range, and back to the human poke
## when the enemy outruns the animal kit — and stays put when it can already hit.
## The transform's own cooldown bounds how often this flips, so the pulls (engage,
## disengage, retreat to heal) cannot thrash tick to tick.
func _preferred_form(bot: SimEntity, target: SimEntity) -> int:
	var other := 1 - bot.form
	if (
		bot.form != AbilitySpec.FORM_HUMAN
		and _is_hurt(bot)
		and _form_has_ready_heal(bot, AbilitySpec.FORM_HUMAN)
	):
		return AbilitySpec.FORM_HUMAN
	# A kiter does not drop to a shorter-range form to engage: it holds the form whose
	# poke reaches farthest and creates distance with its feet instead.
	if bot.stance == AbilityData.STANCE_KITE:
		return _ranged_form(bot)
	if (
		not _form_reaches_with_damage(bot, bot.form, target)
		and _form_reaches_with_damage(bot, other, target)
	):
		return other
	return bot.form


## Whether the bot is hurt enough to want a heal — health under `HEAL_HP_FRACTION`
## of its maximum. A non-combat entity (max_hp 0) is never hurt.
func _is_hurt(bot: SimEntity) -> bool:
	return bot.max_hp > 0 and bot.hp < int(float(bot.max_hp) * HEAL_HP_FRACTION)


## The lowest slot in the bot's `form` bar whose ability has `effect`, passes the
## cast gate (form, resource, cooldown), and — for a damaging ability — can reach
## `target`. -1 when none qualifies. A heal is self-cast and a transform self-aimed,
## so neither needs a reach check.
func _castable_slot(bot: SimEntity, form: int, effect: int, target: SimEntity) -> int:
	var dist := bot.position.distance_to(target.position)
	for spec in _form_specs(bot, form):
		if spec.effect != effect:
			continue
		if not AbilityExecutor.can_cast(bot, spec):
			continue
		if effect == AbilitySpec.EFFECT_DAMAGE and not _reaches(spec, dist):
			continue
		return spec.slot
	return -1


## Whether `form`'s bar holds a heal that is off cooldown right now. Reads the
## cooldown (which survives a transform, keyed by ability id) but neither the
## resource nor the active form, so it answers "would flipping to this form give me
## a heal to cast" from either stance — the resource is left to the post-transform
## cast gate.
func _form_has_ready_heal(bot: SimEntity, form: int) -> bool:
	for spec in _form_specs(bot, form):
		if spec.effect == AbilitySpec.EFFECT_HEAL and bot.ability_cooldowns.get(spec.id, 0) == 0:
			return true
	return false


## Whether `form`'s bar holds a damaging ability whose geometry would land on a
## target `dist` away — the "is this stance's payoff in reach" test that drives a
## transform. Geometry only: it ignores resource and cooldown (which the form swap
## changes), leaving those to the cast gate once the bot is in that form.
func _form_reaches_with_damage(bot: SimEntity, form: int, target: SimEntity) -> bool:
	var dist := bot.position.distance_to(target.position)
	for spec in _form_specs(bot, form):
		if spec.effect == AbilitySpec.EFFECT_DAMAGE and _reaches(spec, dist):
			return true
	return false


## The abilities on `form`'s bar, lowest slot first — the specs the form's slot ids
## resolve to, skipping empty slots and ids absent from the catalog. Slot order
## keeps every scan over a form deterministic, like the rest of the simulation.
func _form_specs(bot: SimEntity, form: int) -> Array[AbilitySpec]:
	var specs: Array[AbilitySpec] = []
	var slots: Dictionary = bot.kit.get(form, {})
	for slot in SLOT_COUNT:
		if not slots.has(slot):
			continue
		var ability_id: int = slots[slot]
		if AbilityData.has_ability(ability_id):
			specs.append(AbilityData.spec(ability_id))
	return specs


## Whether a cast of `spec` aimed straight at an enemy `dist` away would actually
## strike it — mirroring the executor's landing geometry so the bot never spends a
## cast on empty air. A UNIT ability reaches any enemy within range; a GROUND area
## lands on the target (pulled in to range) and hits if the target sits inside its
## radius; a SKILLSHOT flies the full range along the aim, so it strikes only an
## enemy in the band one radius around that range.
func _reaches(spec: AbilitySpec, dist: float) -> bool:
	match spec.target_kind:
		AbilitySpec.TARGET_UNIT:
			return dist <= spec.range
		AbilitySpec.TARGET_GROUND:
			return dist <= spec.range + spec.radius
		AbilitySpec.TARGET_SKILLSHOT:
			return absf(dist - spec.range) <= spec.radius
	return false


## Positions a kiter: it holds the enemy inside its skillshot band — backing off when
## the enemy is nearer than the band, closing when it is farther, and holding still
## within it so the poke lands. A kiter whose current form has no skillshot poke (it is
## briefly in the wrong form, about to shift back) just closes like a brawler until the
## stance step returns it to its ranged form. Movement only — the cast step still fires.
func _kite_move(command: InputCommand, bot: SimEntity, target: SimEntity) -> void:
	var to_enemy := target.position - bot.position
	var dist := to_enemy.length()
	if dist <= 0.0:
		return
	var band := _kite_band(bot)
	if band == Vector2.ZERO:
		if dist > STOP_RANGE:
			command.move_dir = to_enemy / dist
		return
	if dist < band.x:
		command.move_dir = -to_enemy / dist
	elif dist > band.y:
		command.move_dir = to_enemy / dist


## The distance band a kiter holds — [range - radius, range + radius] of its current
## form's longest-range skillshot, the window in which that poke actually lands. Zero
## when the form holds no skillshot, which tells `_kite_move` to close like a brawler.
func _kite_band(bot: SimEntity) -> Vector2:
	var best_range := 0.0
	var best_radius := 0.0
	for spec in _form_specs(bot, bot.form):
		if spec.effect != AbilitySpec.EFFECT_DAMAGE:
			continue
		if spec.target_kind != AbilitySpec.TARGET_SKILLSHOT:
			continue
		if spec.range > best_range:
			best_range = spec.range
			best_radius = spec.radius
	if best_range <= 0.0:
		return Vector2.ZERO
	return Vector2(best_range - best_radius, best_range + best_radius)


## A kiter's preferred form: the one whose longest-reaching damaging ability reaches
## farthest, so the kiter always fights from its poke form. A tie, or a kit with no
## damaging ability at all, falls to the human form.
func _ranged_form(bot: SimEntity) -> int:
	if _longest_damage_range(bot, AbilitySpec.FORM_ANIMAL) > _longest_damage_range(
		bot, AbilitySpec.FORM_HUMAN
	):
		return AbilitySpec.FORM_ANIMAL
	return AbilitySpec.FORM_HUMAN


## The range of the farthest-reaching damaging ability on `form`'s bar — how far that
## stance can threaten — or 0 when the form holds no damaging ability.
func _longest_damage_range(bot: SimEntity, form: int) -> float:
	var best := 0.0
	for spec in _form_specs(bot, form):
		if spec.effect == AbilitySpec.EFFECT_DAMAGE and spec.range > best:
			best = spec.range
	return best


func _nearest_enemy(state: SimState, bot: SimEntity) -> SimEntity:
	var nearest: SimEntity = null
	var nearest_dist := INF
	for id in state.entities:
		var other: SimEntity = state.entities[id]
		if other.team == bot.team:
			continue
		var dist := bot.position.distance_to(other.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest
