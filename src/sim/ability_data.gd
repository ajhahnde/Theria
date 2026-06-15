class_name AbilityData
extends RefCounted
## The ability catalog: every ability as a data row, and every hero kit as a map
## from form and slot to an ability id plus that form's resource pool. Pure static
## data — the single source of truth the simulation reads to equip a hero and the
## executor reads to act. New abilities and heroes are added here, by value, with
## no engine or render coupling, so the whole roster stays unit-testable.
##
## "wildkin" is the schema-proving kit: a generic shapeshifter that exercises the
## whole catalog — all four targeting modes, the three effects, a per-form resource,
## and the human/animal transform. It stays as the reference the schema tests drive.
##
## The first tribe's roster is authored on top of it: the **Solane** — savanna big-cat
## shifters. Three mirror heroes, each a human kit plus an animal kit, built
## from the same DAMAGE/HEAL/TRANSFORM primitives but given distinct identities through
## their targeting mix, their tuning, and their resource economy:
##   - **Lion**    — a frontline bruiser: short-range poke, a heavy single-target Maul,
##                   and the deepest self-sustain, on a generous, slow-spending pool.
##   - **Cheetah** — a burst skirmisher: long-range pokes and a repeatable single-target
##                   shred, on a lean, fast-regenerating pool (hit and run).
##   - **Hyena**   — a zone controller: the widest ground areas in both forms for
##                   attrition, on a baseline pool.
##
## The opposing tribe, the **Verdani** — jungle venom-and-shadow shifters — is authored
## on the same primitives, a deliberate foil to the Solane archetypes:
##   - **Snake**     — a venom striker: a long single-target lock, a cheap low-cooldown
##                     Fang Strike, and a heavy Venom Coil payoff, on a mid-tier pool.
##   - **Spider**    — a trapper: the longest, widest, lowest-power ground webs in the
##                     game for pure attrition, on the deepest, slowest-regen pool.
##   - **Chameleon** — an ambusher: a short hard skillshot and the single heaviest hit
##                     in either tribe, on the leanest, fastest-refilling pool.
## In a practice match the player's squad fields the Solane and the bot squad the
## Verdani, so both rosters and all four targeting modes are exercised at once. The
## Verdani's venom and web are now mechanical, not just named: their striking abilities
## carry a lingering status (see AbilitySpec.STATUS_*) — venom is a damage-over-time, web
## a movement slow — so the bite keeps biting and the snare actually snares. Each venom
## ability trades part of its instant power for that lingering bite, so the Verdani lean
## attrition where the Solane stay burst.

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
	# --- Solane: Lion, human form (a short-range bruiser with deep self-sustain) ---
	10:
	{
		"id": 10,
		"name": "Sunfire Lash",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 450.0,
		"radius": 70.0,
		"cost": 25,
		"cooldown_ticks": 36,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 65,
	},
	11:
	{
		"id": 11,
		"name": "Mane Guard",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 35,
		"cooldown_ticks": 150,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 150,  # the deepest heal in the tribe: the bruiser's staying power
	},
	12:
	{
		"id": 12,
		"name": "Lion Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Solane: Lion, animal form (engage area, then a heavy melee burst) --------
	13:
	{
		"id": 13,
		"name": "Pounce",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 350.0,
		"radius": 160.0,
		"cost": 25,
		"cooldown_ticks": 30,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 70,
	},
	14:
	{
		"id": 14,
		"name": "Maul",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 190.0,  # melee: the bruiser must close to land its payoff
		"cost": 35,
		"cooldown_ticks": 48,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 160,  # the hardest single hit in the tribe
	},
	15:
	{
		"id": 15,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Solane: Cheetah, human form (long pokes on a lean, fast pool) ------------
	20:
	{
		"id": 20,
		"name": "Spear Throw",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 750.0,  # the longest reach in the tribe
		"radius": 50.0,  # but a tight line: it must be aimed
		"cost": 20,
		"cooldown_ticks": 24,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 90,
	},
	21:
	{
		"id": 21,
		"name": "Second Wind",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 25,
		"cooldown_ticks": 100,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 80,  # a skirmisher's top-up, not the Lion's wall
	},
	22:
	{
		"id": 22,
		"name": "Cheetah Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Solane: Cheetah, animal form (single-target shred, repeatable) -----------
	23:
	{
		"id": 23,
		"name": "Hamstring",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 280.0,
		"cost": 15,
		"cooldown_ticks": 18,  # the shortest cooldown in the tribe: harass on repeat
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 70,
	},
	24:
	{
		"id": 24,
		"name": "Killing Blow",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 220.0,
		"cost": 35,
		"cooldown_ticks": 50,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 140,
	},
	25:
	{
		"id": 25,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Solane: Hyena, human form (the widest ground zone for attrition) ---------
	30:
	{
		"id": 30,
		"name": "Bone-Hex",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 600.0,
		"radius": 190.0,
		"cost": 30,
		"cooldown_ticks": 40,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 55,
	},
	31:
	{
		"id": 31,
		"name": "Scavenge",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 30,
		"cooldown_ticks": 120,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 100,
	},
	32:
	{
		"id": 32,
		"name": "Hyena Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Solane: Hyena, animal form (a bite, and a wide pack slam) ----------------
	33:
	{
		"id": 33,
		"name": "Rending Bite",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 200.0,
		"cost": 20,
		"cooldown_ticks": 30,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 90,
	},
	34:
	{
		"id": 34,
		"name": "Pack Frenzy",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 320.0,
		"radius": 210.0,  # the widest area in the tribe
		"cost": 35,
		"cooldown_ticks": 44,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 60,
	},
	35:
	{
		"id": 35,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Snake, human form (a long venom poke on a precise pool) ----------
	40:
	{
		"id": 40,
		"name": "Venom Spit",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 650.0,  # a long reach, just shy of the Cheetah's signature spear
		"radius": 55.0,  # but a thin line: it must be aimed
		"cost": 20,
		"cooldown_ticks": 24,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 50,  # trimmed from a pure poke: the rest of the bite is the venom below
		"status": AbilitySpec.STATUS_DOT,  # venom: lingering damage over two seconds
		"status_power": 6,
		"status_duration": 120,
		"status_interval": 30,
	},
	41:
	{
		"id": 41,
		"name": "Shed Skin",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 30,
		"cooldown_ticks": 110,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 90,
	},
	42:
	{
		"id": 42,
		"name": "Serpent Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Snake, animal form (the longest single-target lock, then a payoff) ---
	43:
	{
		"id": 43,
		"name": "Fang Strike",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 360.0,  # the longest single-target lock in either tribe
		"cost": 15,
		"cooldown_ticks": 18,  # cheap and fast: harass on repeat
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 55,  # a lighter strike now that the fang leaves venom
		"status": AbilitySpec.STATUS_DOT,
		"status_power": 5,
		"status_duration": 120,
		"status_interval": 30,
	},
	44:
	{
		"id": 44,
		"name": "Venom Coil",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 300.0,
		"cost": 35,
		"cooldown_ticks": 50,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 105,  # the heavy payoff, now split between the coil and its deep venom
		"status": AbilitySpec.STATUS_DOT,  # the tribe's strongest venom: a heavy lingering bleed
		"status_power": 11,
		"status_duration": 120,
		"status_interval": 30,
	},
	45:
	{
		"id": 45,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Spider, human form (the longest, widest web for attrition) -------
	50:
	{
		"id": 50,
		"name": "Web Snare",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 620.0,
		"radius": 200.0,
		"cost": 30,
		"cooldown_ticks": 38,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 45,  # the lowest per-hit power in either tribe: attrition, now with a snare
		"status": AbilitySpec.STATUS_SLOW,  # web: the strongest, longest slow — the trapper's lock
		"status_power": 45,  # a 45% slow
		"status_duration": 150,
	},
	51:
	{
		"id": 51,
		"name": "Silk Mend",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 30,
		"cooldown_ticks": 120,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 100,
	},
	52:
	{
		"id": 52,
		"name": "Spider Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Spider, animal form (a close bite, then the widest nest) ----------
	53:
	{
		"id": 53,
		"name": "Venom Bite",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 210.0,
		"cost": 20,
		"cooldown_ticks": 30,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 65,  # a lighter bite, the rest delivered as venom
		"status": AbilitySpec.STATUS_DOT,
		"status_power": 5,
		"status_duration": 120,
		"status_interval": 30,
	},
	54:
	{
		"id": 54,
		"name": "Web Nest",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_GROUND,
		"range": 340.0,
		"radius": 220.0,  # the widest area in either tribe
		"cost": 35,
		"cooldown_ticks": 46,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 50,  # a touch lighter, the nest now also snares the zone
		"status": AbilitySpec.STATUS_SLOW,  # web: a shorter, wider slow than the snare
		"status_power": 30,  # a 30% slow
		"status_duration": 90,
	},
	55:
	{
		"id": 55,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Chameleon, human form (a short, hard skillshot on a lean pool) ----
	60:
	{
		"id": 60,
		"name": "Tongue Lash",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 380.0,  # short: the ambusher fights up close
		"radius": 60.0,
		"cost": 25,
		"cooldown_ticks": 30,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 95,  # a heavy poke for its range
	},
	61:
	{
		"id": 61,
		"name": "Blend",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 1,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 25,
		"cooldown_ticks": 100,
		"effect": AbilitySpec.EFFECT_HEAL,
		"power": 75,  # a skirmisher's top-up, not a wall
	},
	62:
	{
		"id": 62,
		"name": "Chameleon Form",
		"form": AbilitySpec.FORM_HUMAN,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
	# --- Verdani: Chameleon, animal form (a cheap dart, then the heaviest ambush) ---
	63:
	{
		"id": 63,
		"name": "Color Dart",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 0,
		"target_kind": AbilitySpec.TARGET_SKILLSHOT,
		"range": 300.0,
		"radius": 50.0,
		"cost": 15,
		"cooldown_ticks": 20,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 60,
	},
	64:
	{
		"id": 64,
		"name": "Ambush",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 2,
		"target_kind": AbilitySpec.TARGET_UNIT,
		"range": 200.0,  # melee: the payoff for closing the gap
		"cost": 35,
		"cooldown_ticks": 52,
		"effect": AbilitySpec.EFFECT_DAMAGE,
		"power": 165,  # the single heaviest hit in either tribe
	},
	65:
	{
		"id": 65,
		"name": "Human Form",
		"form": AbilitySpec.FORM_ANIMAL,
		"slot": 3,
		"target_kind": AbilitySpec.TARGET_SELF,
		"cost": 0,
		"cooldown_ticks": 60,
		"effect": AbilitySpec.EFFECT_TRANSFORM,
	},
}

## Bot stance per kit: how a bot positions a hero it drives. BRAWL — the default for
## any kit that names no stance — closes the gap and shifts toward whichever form can
## land a hit. KITE holds the kit's ranged poke and keeps the enemy at arm's length,
## fighting hit-and-run from its skillshot band rather than committing to melee. Read by
## BotController and stamped onto the hero at equip; a player-driven hero ignores it.
const STANCE_BRAWL := 0
const STANCE_KITE := 1


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
	# --- Solane (savanna big-cats), the v0.1 mirror tribe ---------------------
	"lion":
	{
		# A bruiser: a generous pool that spends slowly, to back the deep heal and
		# the heavy Maul.
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 120, "regen_ticks": 10},
			AbilitySpec.FORM_ANIMAL: {"max": 120, "regen_ticks": 10},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 10, 1: 11, 3: 12},
			AbilitySpec.FORM_ANIMAL: {0: 13, 2: 14, 3: 15},
		},
	},
	"cheetah":
	{
		# A skirmisher: a lean pool that refills fast, to chain cheap pokes and the
		# low-cooldown Hamstring. A kiter — it holds its long Spear Throw range.
		"stance": STANCE_KITE,
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 80, "regen_ticks": 8},
			AbilitySpec.FORM_ANIMAL: {"max": 80, "regen_ticks": 8},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 20, 1: 21, 3: 22},
			AbilitySpec.FORM_ANIMAL: {0: 23, 2: 24, 3: 25},
		},
	},
	"hyena":
	{
		# A zone controller: a baseline pool feeding the wide ground areas.
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 100, "regen_ticks": 12},
			AbilitySpec.FORM_ANIMAL: {"max": 100, "regen_ticks": 12},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 30, 1: 31, 3: 32},
			AbilitySpec.FORM_ANIMAL: {0: 33, 2: 34, 3: 35},
		},
	},
	# --- Verdani (jungle venom-and-shadow), the opposing tribe ----------------
	"snake":
	{
		# A striker: a precise mid-tier pool, between the Cheetah's lean and the
		# Hyena's baseline, to feed the cheap Fang Strike and the heavy Coil.
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 90, "regen_ticks": 9},
			AbilitySpec.FORM_ANIMAL: {"max": 90, "regen_ticks": 9},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 40, 1: 41, 3: 42},
			AbilitySpec.FORM_ANIMAL: {0: 43, 2: 44, 3: 45},
		},
	},
	"spider":
	{
		# A trapper: the deepest pool on the slowest regen, to sustain the wide,
		# cheap-per-cast webs over a long attrition.
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 110, "regen_ticks": 13},
			AbilitySpec.FORM_ANIMAL: {"max": 110, "regen_ticks": 13},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 50, 1: 51, 3: 52},
			AbilitySpec.FORM_ANIMAL: {0: 53, 2: 54, 3: 55},
		},
	},
	"chameleon":
	{
		# An ambusher: the leanest pool on the fastest regen, to land a burst and
		# refill for the next one — the most boom-and-bust economy of either tribe. A
		# kiter — it darts in and out at its Tongue Lash range rather than brawling.
		"stance": STANCE_KITE,
		"resource":
		{
			AbilitySpec.FORM_HUMAN: {"max": 70, "regen_ticks": 7},
			AbilitySpec.FORM_ANIMAL: {"max": 70, "regen_ticks": 7},
		},
		"abilities":
		{
			AbilitySpec.FORM_HUMAN: {0: 60, 1: 61, 3: 62},
			AbilitySpec.FORM_ANIMAL: {0: 63, 2: 64, 3: 65},
		},
	},
}


## The tribes: each tribe's hero roster, in seating order. The single source of which
## heroes form which tribe — the client reads it to seat a tribe-vs-tribe match, and the
## roster order fixes each hero's squad slot. The wildkin reference kit is deliberately
## in no tribe. v0.1 ships two tribes; a match pairs one against another (see
## `opposing_tribe`).
const TRIBE := {
	"solane": ["lion", "cheetah", "hyena"],
	"verdani": ["snake", "spider", "chameleon"],
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


## The tribe a hero kit belongs to, or "" if the kit is in no tribe (the wildkin reference
## kit, or an unknown name). A pure lookup over the roster data.
static func tribe_of(kit_id: String) -> String:
	for tribe in TRIBE:
		if (TRIBE[tribe] as Array).has(kit_id):
			return tribe
	return ""


## The tribe a given tribe is matched against — the next other tribe in declaration order.
## v0.1 fields exactly two, so this is simply "the other one"; returns `tribe` itself if
## it is the only tribe defined.
static func opposing_tribe(tribe: String) -> String:
	for other in TRIBE:
		if other != tribe:
			return other
	return tribe
