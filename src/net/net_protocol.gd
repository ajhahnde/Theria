class_name NetProtocol
extends RefCounted
## The wire contract between the authoritative server and its clients.
##
## Pure, engine-free serialization: it turns an InputCommand into a small Array, and
## a whole SimState into a compact, fixed-layout binary record (a PackedByteArray),
## and back, with no transport or rendering coupling. The snapshot is packed tight — a
## short header plus one fixed byte record per entity, floats narrowed to 32 bits — so
## a full world stays inside a single unreliable datagram rather than fragmenting above
## the transport MTU. Keeping the shaping here — separate from the socket layer in
## NetSession — is what lets the round trip be unit-tested headlessly, exactly like the
## simulation core.
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

const PROTOCOL_VERSION := 4

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


## Encodes the authoritative world into a snapshot byte record: an 11-byte
## header — tick (u32), `ack` (i32), winner (i8), entity count (u16) — followed by one
## fixed entity record per encoded entity in insertion order. `ack` is the last client input
## sequence the server has applied (`-1` when none); the client reads it to prune and
## replay its pending inputs, and `decode_snapshot` ignores it (a transport marker, not
## world state) — `decode_snapshot_ack` reads it alone, straight from the header,
## without decoding the entities. Insertion order is preserved so the decoded world
## iterates identically to the server's — deterministic rendering. Packing the world
## this tight keeps a full creep wave inside one unreliable datagram.
##
## `visible_ids` is the fog-of-war filter: when non-empty, only entities whose id is in it are
## written (and the count reflects that), so an enemy a team cannot see never crosses the wire —
## the fog is authoritative, not a client dim. Empty (the default) writes the whole world, the
## pre-fog behaviour every other caller and the round-trip tests rely on. The wire shape is
## unchanged — a filtered snapshot is just a smaller entity count — so PROTOCOL_VERSION is not
## affected: a filtered server and an unfiltered one differ only in how many rows they send.
static func encode_snapshot(
	state: SimState, ack: int = -1, visible_ids: Dictionary = {}
) -> PackedByteArray:
	var ids: Array = []
	for id in state.entities:
		if visible_ids.is_empty() or visible_ids.has(id):
			ids.append(id)
	var buf := StreamPeerBuffer.new()
	buf.put_u32(state.tick)
	buf.put_32(ack)
	buf.put_8(state.winner)
	buf.put_u16(ids.size())
	for id in ids:
		_encode_entity(buf, state.entities[id])
	return buf.data_array


## Reads the input ack out of a snapshot's header without decoding its entities — the
## client needs it every tick to reconcile, but not the whole world. The ack is the
## second header field: a signed 32-bit int at byte offset 4.
static func decode_snapshot_ack(bytes: PackedByteArray) -> int:
	return bytes.decode_s32(4)


## Rebuilds a SimState from a snapshot byte record. The result is a render target, not
## a simulation: it carries no id allocator and is never stepped on the client.
static func decode_snapshot(bytes: PackedByteArray) -> SimState:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(0)
	var state := SimState.new()
	state.tick = buf.get_u32()
	buf.get_32()  # ack — a transport marker, read via decode_snapshot_ack, not world state
	state.winner = buf.get_8()
	var count := buf.get_u16()
	for _i in count:
		state.add_entity(_decode_entity(buf))
	return state


## Fixed entity byte record, by field (little-endian, 37 bytes):
##   id u32  team u8  pos.x f32  pos.y f32  move_speed f32  hp i16  max_hp i16
##   attack_damage i16  attack_range f32  attack_cooldown_ticks u16  cooldown u16
##   flags u8 (structure|nexus|creep bitmask)  lane u8  waypoint_index u16
##   respawn_ticks u16 (0 for a living unit; a downed hero's countdown, so the client raises
##   its death screen and ticks the timer straight off the snapshot)
## Floats are narrowed to 32 bits: positions are Vector2 (already 32-bit) so they round
## trip exactly, and the round-number tunings are exact in 32 bits too. The integer
## widths cover the v0.1 tuning with headroom (hp and damage sit well inside a signed
## 16-bit range); a tuning that outgrows a field must widen it here in lockstep with a
## PROTOCOL_VERSION bump.
static func _encode_entity(buf: StreamPeerBuffer, entity: SimEntity) -> void:
	var flags := 0
	if entity.is_structure:
		flags |= _FLAG_STRUCTURE
	if entity.is_nexus:
		flags |= _FLAG_NEXUS
	if entity.is_creep:
		flags |= _FLAG_CREEP
	buf.put_u32(entity.id)
	buf.put_u8(entity.team)
	buf.put_float(entity.position.x)
	buf.put_float(entity.position.y)
	buf.put_float(entity.move_speed)
	buf.put_16(entity.hp)
	buf.put_16(entity.max_hp)
	buf.put_16(entity.attack_damage)
	buf.put_float(entity.attack_range)
	buf.put_u16(entity.attack_cooldown_ticks)
	buf.put_u16(entity.cooldown)
	buf.put_u8(flags)
	buf.put_u8(entity.lane)
	buf.put_u16(entity.waypoint_index)
	buf.put_u16(entity.respawn_ticks)


static func _decode_entity(buf: StreamPeerBuffer) -> SimEntity:
	var id := buf.get_u32()
	var team := buf.get_u8()
	var pos := Vector2(buf.get_float(), buf.get_float())
	var move_speed := buf.get_float()
	var entity := SimEntity.new(id, team, pos, move_speed)
	entity.hp = buf.get_16()
	entity.max_hp = buf.get_16()
	entity.attack_damage = buf.get_16()
	entity.attack_range = buf.get_float()
	entity.attack_cooldown_ticks = buf.get_u16()
	entity.cooldown = buf.get_u16()
	var flags := buf.get_u8()
	entity.is_structure = (flags & _FLAG_STRUCTURE) != 0
	entity.is_nexus = (flags & _FLAG_NEXUS) != 0
	entity.is_creep = (flags & _FLAG_CREEP) != 0
	entity.lane = buf.get_u8()
	entity.waypoint_index = buf.get_u16()
	entity.respawn_ticks = buf.get_u16()
	return entity
