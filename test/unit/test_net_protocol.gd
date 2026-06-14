extends GutTest
## Round-trip checks on the wire protocol. These run headless and free of any
## socket or engine-networking coupling: they exercise the exact encode/decode
## the live server and client use, so a snapshot that survives the trip here
## renders identically on a real client. The transport itself (NetSession) is an
## ENet surface verified by the headless host smoke, not these unit tests.


func test_protocol_version_is_pinned() -> void:
	# The netcode compatibility axis. A wire-shape change must bump this in the
	# same commit; this guard makes an accidental drift fail the suite.
	assert_eq(NetProtocol.PROTOCOL_VERSION, 3)


func test_input_round_trips_with_its_sequence_number() -> void:
	var command := InputCommand.new()
	command.move_dir = Vector2(-1.0, 0.5)
	var data := NetProtocol.encode_input(42, command)
	assert_eq(NetProtocol.decode_input_seq(data), 42, "the sequence number survives the trip")
	var restored := NetProtocol.decode_input(data)
	assert_eq(restored.move_dir, command.move_dir, "the move direction survives the trip")


func test_snapshot_carries_the_input_ack() -> void:
	# The ack lets the client prune the inputs the server has applied and replay only
	# the rest. It rides the snapshot header and is read without decoding the world.
	var snapshot := NetProtocol.encode_snapshot(SimState.new(), 7)
	assert_eq(NetProtocol.decode_snapshot_ack(snapshot), 7, "the last applied input seq is carried")
	var no_input := NetProtocol.encode_snapshot(SimState.new())
	assert_eq(NetProtocol.decode_snapshot_ack(no_input), -1, "no input applied -> -1")


func test_an_empty_snapshot_is_just_the_header() -> void:
	# Header only: tick u32, ack i32, winner i8, entity count u16 = 11 bytes. The
	# snapshot is packed bytes, not a Variant container.
	var bytes := NetProtocol.encode_snapshot(SimState.new())
	assert_true(bytes is PackedByteArray, "the snapshot is a packed byte record")
	assert_eq(bytes.size(), 11, "an empty world encodes to the 11-byte header alone")


func test_a_full_snapshot_fits_in_one_unreliable_datagram() -> void:
	# The opening creep wave is the heaviest world the walking skeleton sends. Packed,
	# it must fit one datagram so the snapshot is not fragmented above the transport
	# MTU (~1392 bytes) — the regression guard for the binary wire format.
	var state := _opening_wave_state()
	assert_gt(state.entities.size(), 20, "the opening wave is a heavy world")
	var bytes := NetProtocol.encode_snapshot(state)
	assert_lt(bytes.size(), 1392, "the packed snapshot fits one datagram, below the MTU")


func test_a_populated_snapshot_round_trips_every_field() -> void:
	var state := _populated_state()
	var restored := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(state))

	assert_eq(restored.tick, state.tick, "the tick is carried")
	assert_eq(restored.entities.size(), state.entities.size(), "every entity is carried")
	for id in state.entities:
		var original: SimEntity = state.entities[id]
		var copy: SimEntity = restored.get_entity(id)
		assert_not_null(copy, "entity %d survives the trip" % id)
		if copy == null:
			continue
		assert_eq(copy.id, original.id)
		assert_eq(copy.team, original.team)
		assert_eq(copy.position, original.position)
		assert_eq(copy.move_speed, original.move_speed)
		assert_eq(copy.hp, original.hp)
		assert_eq(copy.max_hp, original.max_hp)
		assert_eq(copy.attack_damage, original.attack_damage)
		assert_eq(copy.attack_range, original.attack_range)
		assert_eq(copy.attack_cooldown_ticks, original.attack_cooldown_ticks)
		assert_eq(copy.cooldown, original.cooldown)
		assert_eq(copy.is_structure, original.is_structure)
		assert_eq(copy.is_nexus, original.is_nexus)
		assert_eq(copy.is_creep, original.is_creep)
		assert_eq(copy.lane, original.lane)
		assert_eq(copy.waypoint_index, original.waypoint_index)


func test_snapshot_preserves_entity_order() -> void:
	# Insertion order keeps server and client iteration identical, which keeps
	# rendering and any future client-side logic deterministic.
	var state := _populated_state()
	var restored := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(state))
	assert_eq(restored.entities.keys(), state.entities.keys())


func test_snapshot_carries_the_winner() -> void:
	var state := SimState.new()
	state.winner = 1
	var restored := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(state))
	assert_eq(restored.winner, 1, "a decided match is carried so the client can show it")
	assert_true(restored.is_match_over())


## A representative world — structures, both heroes, and a creep — advanced a few
## ticks so positions, cooldowns, and hp carry non-default values for the trip.
func _populated_state() -> SimState:
	var sim := SimCore.new()
	sim.spawn_structures()
	sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	sim.add_hero(1, MapData.spawn_for_team(1), 300.0)
	sim.add_creep(0, 0, MapData.lane_path(0, 0)[0])
	for _i in 5:
		sim.step({})
	return sim.state


## The heaviest world the walking skeleton broadcasts: both teams' structures, both
## heroes, and a full creep wave on every lane. The first wave spawns on tick 0, so a
## single step seeds it.
func _opening_wave_state() -> SimState:
	var sim := SimCore.new()
	sim.spawn_structures()
	sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	sim.add_hero(1, MapData.spawn_for_team(1), 300.0)
	sim.step({})
	return sim.state
