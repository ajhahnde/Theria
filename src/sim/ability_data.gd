class_name AbilityData
extends RefCounted
## The ability catalog: every ability as a data row, and every hero kit as a map
## from form and slot to an ability id plus that form's resource pool. Pure static
## data — the single source of truth the simulation reads to equip a hero and the
## executor reads to act. New abilities and heroes are added here, by value, with
## no engine or render coupling, so the whole roster stays unit-testable.
##
## v0.1 ships one proving kit, "wildkin": a generic shapeshifter that exercises the
## whole schema — all four targeting modes, the three effects, a per-form resource,
## and the human/animal transform. The distinct Theria heroes are authored against
## this same catalog in a later slice.

## Ability rows keyed by catalog id. Each row is parsed on demand into a typed
## AbilitySpec by `spec`; a sparse row leans on the spec defaults. The dictionary's
## insertion order is stable, which keeps any iteration over the roster
## deterministic, like the rest of the simulation.
const ABILITIES := {
	# --- wildkin, human form -------------------------------------------------
	1:
	{
		"id": 1,
		"name": "Spirit Bolt",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 600.0,
		"radius": 60.0,  # a tight bolt: clips enemies at its landing point
		"cost": 20,
		"cooldown_ticks": 30,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 80,
	},
	2:
	{
		"id": 2,
		"name": "Mend",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 30,
		"cooldown_ticks": 120,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 100,
	},
	3:
	{
		"id": 3,
		"name": "Beast Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- wildkin, animal form ------------------------------------------------
	4:
	{
		"id": 4,
		"name": "Pounce",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 400.0,
		"radius": 150.0,  # an area slam: every enemy inside the circle is struck
		"cost": 20,
		"cooldown_ticks": 24,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 60,
	},
	5:
	{
		"id": 5,
		"name": "Rend",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 200.0,
		"cost": 30,
		"cooldown_ticks": 48,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 120,
	},
	6:
	{
		"id": 6,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
}

## Hero kits keyed by kit id. A kit names, per form, the resource pool (`max` and
## the regen interval `regen_ticks` — one resource point restored every that many
## ticks, 0 for none) and the slot-to-ability-id bar. A hero equipped with a kit
## starts in human form with that form's resource full. Integer regen on a tick
## interval keeps resource growth deterministic, like the cooldown counters.
const KITS := {
	"wildkin":
	{
		"resource":
		{
			# Human "Focus" and animal "Ferocity": same shape, distinct pools the
			# transform swaps between, so each stance meters its own casts.
			AbilitySpec.FORM_HUMAN: {"max": 100, "regen_ticks": 12},
			AbilitySpec.FORM_ANIMAL: {"max": 100, "regen_ticks": 12},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 1, 1: 2, 3: 3},
			AbilitySpec.FORM_ANIMAL: {0: 4, 2: 5, 3: 6},
		},
	},
}


## The typed spec for a catalog id. Parses the row on demand — the catalog is small
## and the executor caches nothing, so a spec is always read fresh by value.
static func spec(id: int) -> AbilitySpec:
	return AbilitySpec.from_dict(ABILITIES.get(id, {}))


## Whether an ability id exists in the catalog.
static func has_ability(id: int) -> bool:
	return ABILITIES.has(id)


## A kit definition by id, or an empty dictionary if unknown.
static func kit(kit_id: String) -> Dictionary:
	return KITS.get(kit_id, {})
