class_name NetProtocol
extends RefCounted
## The wire contract between the authoritative server and its clients.
##
## Pure, engine-free serialization: it turns an InputCommand or a whole SimState
## into plain Variant data (Arrays / Dictionaries the high-level multiplayer layer
## encodes for us) and back, with no transport or rendering coupling. Keeping it
## here — separate from the socket layer in NetSession — is what lets the round
## trip be unit-tested headlessly, exactly like the simulation core.
##
## The server is authoritative, but a client predicts its own hero locally and
## reconciles against each snapshot. The wire carries two sequence markers for
## that loop: every input is stamped with a client sequence number, and every
## snapshot echoes back the last input sequence the server has applied (its `ack`),
## so the client knows which of its pending inputs to replay.
##
## PROTOCOL_VERSION is the netcode compatibility axis — peers exchange it on
## connect and a mismatch is refused, so an old client cannot desync against a
## newer server. Bump it on any wire-shape change here.

const PROTOCOL_VERSION := 2

## Bit positions for the packed entity-flags field (slot 11 of an entity row).
const _FLAG_STRUCTURE := 1
const _FLAG_NEXUS := 2
const _FLAG_CREEP := 4


## Encodes one tick of intent for a single entity, stamped with the client's
## monotonic input sequence number so the server can acknowledge it and the client
## can match the ack back to a pending input. Only the move direction is carried as
## intent today; richer intent (abilities) extends this row without a reshape.
static func encode_input(seq: int, command: InputCommand) -> Array:
	return [seq, command.move_dir.x, command.move_dir.y]


## The sequence number stamped on an encoded input, read without rebuilding the
## command — the server stores it as the per-peer ack.
static func decode_input_seq(data: Array) -> int:
	return data[0]


static func decode_input(data: Array) -> InputCommand:
	var command := InputCommand.new()
	command.move_dir = Vector2(data[1], data[2])
	return command


## Encodes the full authoritative world into a snapshot: the tick, the winner,
## `ack` (the last client input sequence the server has applied — `-1` when no
## remote input has been processed), and every entity as a fixed-order row.
## Insertion order is preserved so the decoded state iterates identically to the
## server's — deterministic rendering. The client reads `ack` to prune and replay
## its pending inputs; `decode_snapshot` ignores it (it is a transport marker, not
## world state), so it is read straight off the raw dict.
static func encode_snapshot(state: SimState, ack: int = -1) -> Dictionary:
	var rows: Array = []
	for id in state.entities:
		rows.append(_encode_entity(state.entities[id]))
	return {"tick": state.tick, "winner": state.winner, "ack": ack, "entities": rows}


## Rebuilds a SimState from a snapshot. The result is a render target, not a
## simulation: it carries no id allocator and is never stepped on the client.
static func decode_snapshot(data: Dictionary) -> SimState:
	var state := SimState.new()
	state.tick = data["tick"]
	state.winner = data["winner"]
	for row in data["entities"]:
		state.add_entity(_decode_entity(row))
	return state


## Fixed entity row, by slot:
##   0 id  1 team  2 pos.x  3 pos.y  4 move_speed  5 hp  6 max_hp
##   7 attack_damage  8 attack_range  9 attack_cooldown_ticks  10 cooldown
##   11 flags (structure|nexus|creep bitmask)  12 lane  13 waypoint_index
static func _encode_entity(entity: SimEntity) -> Array:
	var flags := 0
	if entity.is_structure:
		flags |= _FLAG_STRUCTURE
	if entity.is_nexus:
		flags |= _FLAG_NEXUS
	if entity.is_creep:
		flags |= _FLAG_CREEP
	return [
		entity.id,
		entity.team,
		entity.position.x,
		entity.position.y,
		entity.move_speed,
		entity.hp,
		entity.max_hp,
		entity.attack_damage,
		entity.attack_range,
		entity.attack_cooldown_ticks,
		entity.cooldown,
		flags,
		entity.lane,
		entity.waypoint_index,
	]


static func _decode_entity(row: Array) -> SimEntity:
	var entity := SimEntity.new(row[0], row[1], Vector2(row[2], row[3]), row[4])
	entity.hp = row[5]
	entity.max_hp = row[6]
	entity.attack_damage = row[7]
	entity.attack_range = row[8]
	entity.attack_cooldown_ticks = row[9]
	entity.cooldown = row[10]
	var flags: int = row[11]
	entity.is_structure = (flags & _FLAG_STRUCTURE) != 0
	entity.is_nexus = (flags & _FLAG_NEXUS) != 0
	entity.is_creep = (flags & _FLAG_CREEP) != 0
	entity.lane = row[12]
	entity.waypoint_index = row[13]
	return entity
