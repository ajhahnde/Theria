class_name AbilitySpec
extends RefCounted
## The immutable definition of one ability — its targeting, cost, cooldown, and
## effect. Pure tuning data, parsed from the ability catalog; it owns no state and
## never mutates the world (the executor reads a spec to act). Keeping abilities as
## data, not code, lets the whole roster live in one catalog and be unit-tested by
## value.
##
## Theria heroes are shapeshifters: every hero carries a human kit and an animal
## kit, and a spec belongs to exactly one `form`. A spec is only castable while its
## form is the caster's active form, which is what makes the two stances play as
## two distinct kits sharing one hero.

## Active form a spec belongs to. A hero swaps between the two with a TRANSFORM
## ability; cooldowns and the per-form resource carry across the swap.
const FORM_HUMAN := 0
const FORM_ANIMAL := 1

## How an ability picks what it hits.
##   SELF      — the caster (heals, transforms, self-buffs); no aim.
##   SKILLSHOT — aimed: a point defines a direction, the shot lands at the clamped
##               range along it and strikes there. Dodgeable.
##   GROUND    — a point on the field (clamped to range): an area lands there.
##   UNIT      — a locked target entity within range; the effect cannot miss.
const TARGET_SELF := 0
const TARGET_SKILLSHOT := 1
const TARGET_GROUND := 2
const TARGET_UNIT := 3

## What an ability does where it lands.
##   DAMAGE    — subtracts `power` hp from each enemy struck.
##   HEAL      — restores `power` hp to the caster (clamped to max_hp).
##   TRANSFORM — swaps the caster to its other form (and that form's resource).
const EFFECT_DAMAGE := 0
const EFFECT_HEAL := 1
const EFFECT_TRANSFORM := 2

## A lingering status an ability leaves on each enemy it strikes, on top of its
## immediate effect — the schema behind the Verdani's venom and web flavor.
##   NONE — leaves nothing (the default; every Solane ability and every heal/transform).
##   DOT  — venom: deals `status_power` hp every `status_interval` ticks for
##          `status_duration` ticks, so the bite keeps biting after it lands.
##   SLOW — web: scales the target's move speed by (100 - `status_power`) percent for
##          `status_duration` ticks, so a snared enemy crawls.
##   STUN — a hard lock: for `status_duration` ticks the target cannot move, cast, or
##          auto-attack. A stun has no magnitude — `status_power` and `status_interval`
##          are unused; it either holds the unit or it does not.
## A status rides on the ability's target selection — it is laid by the DAMAGE/area
## path on every enemy struck, so a SELF heal or transform never carries one.
const STATUS_NONE := 0
const STATUS_DOT := 1
const STATUS_SLOW := 2
const STATUS_STUN := 3

## Catalog id (unique across the roster) and display name.
var id: int = 0
var name: String = ""

## The form this spec is cast from, and the slot it occupies in that form's kit
## (0..3, the Q/W/E/R bar). One id per (form, slot) within a kit.
var form: int = FORM_HUMAN
var slot: int = 0

var target_kind: int = TARGET_SELF

## Maximum cast distance (world units) for an aimed/targeted ability; ignored for
## SELF. `radius` is the area struck around the landing point: every enemy inside
## the circle is hit. A SKILLSHOT or GROUND ability gives it a small-to-large value
## (a tight bolt up to a wide slam); SELF and UNIT abilities ignore it (UNIT strikes
## its one locked target).
var range: float = 0.0
var radius: float = 0.0

## Resource spent to cast (see SimEntity's per-form resource) and the cooldown, in
## ticks, the ability goes onto once cast.
var cost: int = 0
var cooldown_ticks: int = 0

var effect: int = EFFECT_DAMAGE

## Magnitude of the effect: hp for DAMAGE/HEAL. Unused by TRANSFORM, which always
## swaps to the caster's other form.
var power: int = 0

## The lingering status (above) laid on each enemy this ability strikes, and its
## tuning. `status` selects the kind (NONE leaves the ability instant-only).
## `status_power` is hp-per-interval for DOT, percent-slow for SLOW; `status_duration`
## is how long it lasts in ticks; `status_interval` is how often a DOT bites (clamped
## to >= 1 when applied, so it never ticks more than once a tick; ignored by SLOW).
var status: int = STATUS_NONE
var status_power: int = 0
var status_duration: int = 0
var status_interval: int = 0


## Builds a spec from one catalog row. Every field defaults, so a sparse row only
## states what it changes — keeping the catalog terse and the parse total.
static func from_dict(d: Dictionary) -> AbilitySpec:
	var spec := AbilitySpec.new()
	spec.id = d.get("id", 0)
	spec.name = d.get("name", "")
	spec.form = d.get("form", FORM_HUMAN)
	spec.slot = d.get("slot", 0)
	spec.target_kind = d.get("target_kind", TARGET_SELF)
	spec.range = d.get("range", 0.0)
	spec.radius = d.get("radius", 0.0)
	spec.cost = d.get("cost", 0)
	spec.cooldown_ticks = d.get("cooldown_ticks", 0)
	spec.effect = d.get("effect", EFFECT_DAMAGE)
	spec.power = d.get("power", 0)
	spec.status = d.get("status", STATUS_NONE)
	spec.status_power = d.get("status_power", 0)
	spec.status_duration = d.get("status_duration", 0)
	spec.status_interval = d.get("status_interval", 0)
	return spec
