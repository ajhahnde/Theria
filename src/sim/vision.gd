class_name Vision
extends RefCounted
## Per-team fog-of-war vision over the authoritative world.
##
## A team sees its own units always, plus any unit standing within the sight radius of one of
## those units — a plain radius reveal, no terrain occlusion (a wall does not block sight in v1;
## that is a later slice that can read MapData.obstacles()). Pure data over a SimState, like
## MapData and the simulation core: no engine, render, or global-state coupling, so it is shared
## by the server's snapshot filter, the client's render, and the headless tests, and replays
## identically.
##
## The server runs `visible_ids` per receiving team and only ever sends that team the entities it
## can see (NetProtocol.encode_snapshot's filter), so an enemy in fog never crosses the wire — the
## fog is authoritative, not a client dim a maphack could peel back. The renderer feeds
## `sight_sources` to the fog overlay so the lit reveal matches exactly which units are sent.

## How far each kind of unit sees, in world units. A hero scouts widest; a tower/nexus holds a
## fixed ward over its approach; a lane creep lights only its immediate front. Tuned lighter than a
## full MOBA's wards (there are none yet) so map control still rewards moving a hero up.
const HERO_SIGHT := 1400.0
const CREEP_SIGHT := 900.0
const STRUCTURE_SIGHT := 1300.0


## How far `entity` sees, or 0 for a unit that grants no vision (a pure mover, or a downed hero —
## a dead unit's ward goes dark until it respawns). The one place the per-kind radii are resolved,
## read by both `sight_sources` and `visible_ids`.
static func sight_radius(entity: SimEntity) -> float:
	if entity.is_dead():
		return 0.0
	if entity.is_hero:
		return HERO_SIGHT
	if entity.is_creep:
		return CREEP_SIGHT
	if entity.is_structure:
		return STRUCTURE_SIGHT
	return 0.0


## The reveal set for `team`: one `{center, radius}` per living friendly unit that grants vision,
## in entity insertion order. Shared by the fog render (the lit circles) and `visible_ids` (the
## membership test), so what is drawn lit is exactly what is sent.
static func sight_sources(state: SimState, team: int) -> Array:
	var sources: Array = []
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.team != team:
			continue
		var radius := sight_radius(entity)
		if radius > 0.0:
			sources.append({"center": entity.position, "radius": radius})
	return sources


## The ids `team` can see, as an id->true set for O(1) membership: every own-team entity always
## (you never lose sight of your own units, even a downed hero on the respawn clock), plus any
## entity whose centre lies within the radius of one of the team's sight sources. Pure and
## insertion-ordered, so the server filters every client's snapshot deterministically.
static func visible_ids(state: SimState, team: int) -> Dictionary:
	var sources := sight_sources(state, team)
	var visible: Dictionary = {}
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.team == team:
			visible[id] = true
			continue
		for source in sources:
			if entity.position.distance_to(source["center"]) <= source["radius"]:
				visible[id] = true
				break
	return visible
