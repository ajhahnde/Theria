extends GutTest
## The N2 client-prediction invariant, exercised without any networking: a client
## that replays its un-acknowledged inputs onto the latest authoritative snapshot
## must land its hero exactly where the server's own simulation will — prediction
## and reconciliation never diverge from authority.
##
## The reconcile loop here mirrors `main.gd`'s `_predicted_state`: decode the
## snapshot, drop the inputs at or below the server's ack, replay the rest through
## the shared `SimCore.apply_movement`. Keeping it pure lets the round trip be
## checked headlessly, exactly like the protocol and simulation cores.

const HERO_SPEED := 320.0


func test_replayed_prediction_matches_the_authoritative_position() -> void:
	var inputs := [
		_command(Vector2.RIGHT),
		_command(Vector2.RIGHT),
		_command(Vector2.UP),
		_command(Vector2(1.0, 1.0)),
		_command(Vector2.LEFT),
	]
	# The server has applied the first three inputs (acked up to seq 3); the client
	# still holds all five as pending until it reconciles.
	var acked := 3
	var server := SimCore.new()
	server.spawn_creeps = false
	var hero_id := server.add_hero(1, Vector2(500.0, 500.0), HERO_SPEED)
	for i in acked:
		server.step({hero_id: inputs[i]})

	# The client reconciles against the snapshot taken at this ack: prune the
	# applied inputs, then replay the remainder onto its predicted hero.
	var pending := _all_pending(inputs)
	var snapshot := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(server.state, acked))
	var predicted := snapshot.get_entity(hero_id)
	while not pending.is_empty() and pending[0]["seq"] <= acked:
		pending.pop_front()
	for entry in pending:
		SimCore.apply_movement(predicted, entry["input"])

	# Meanwhile the server applies the remaining inputs for real.
	for i in range(acked, inputs.size()):
		server.step({hero_id: inputs[i]})

	assert_eq(
		predicted.position,
		server.state.get_entity(hero_id).position,
		"the replayed prediction lands on the authoritative position",
	)


func test_reconciliation_prunes_acknowledged_inputs() -> void:
	# Five pending inputs (seq 1..5); an ack of 3 must drop seqs 1..3 and keep 4
	# and 5 — only the inputs the server has not yet applied are replayed.
	var pending: Array[Dictionary] = []
	for seq in range(1, 6):
		pending.append({"seq": seq, "input": _command(Vector2.RIGHT)})
	var ack := 3
	while not pending.is_empty() and pending[0]["seq"] <= ack:
		pending.pop_front()
	assert_eq(pending.size(), 2, "the two un-acked inputs remain")
	assert_eq(pending[0]["seq"], 4, "pruning stops at the first un-acked input")
	assert_eq(pending[1]["seq"], 5)


func test_a_fully_acked_buffer_predicts_nothing() -> void:
	# When the server has applied every input, replay is empty and the prediction
	# is exactly the snapshot — the client and server agree with no extrapolation.
	var pending: Array[Dictionary] = []
	for seq in range(1, 4):
		pending.append({"seq": seq, "input": _command(Vector2.RIGHT)})
	var ack := 3
	while not pending.is_empty() and pending[0]["seq"] <= ack:
		pending.pop_front()
	assert_eq(pending.size(), 0, "an ack covering every input leaves nothing to replay")


# --- apply_movement: the shared movement sub-step the prediction replays --------


func test_apply_movement_advances_one_tick() -> void:
	var entity := SimEntity.new(1, 0, Vector2.ZERO, 300.0)
	SimCore.apply_movement(entity, _command(Vector2.RIGHT))
	assert_almost_eq(entity.position.x, 300.0 * SimCore.TICK_DELTA, 0.0001)
	assert_almost_eq(entity.position.y, 0.0, 0.0001)


func test_apply_movement_clamps_diagonals() -> void:
	var entity := SimEntity.new(1, 0, Vector2.ZERO, 300.0)
	SimCore.apply_movement(entity, _command(Vector2.ONE))  # length sqrt(2) -> clamps to 1
	assert_almost_eq(entity.position.length(), 300.0 * SimCore.TICK_DELTA, 0.0001)


func test_apply_movement_holds_still_on_null_command() -> void:
	var entity := SimEntity.new(1, 0, Vector2(10.0, -5.0), 300.0)
	SimCore.apply_movement(entity, null)
	assert_eq(entity.position, Vector2(10.0, -5.0), "a null command moves nothing")


# --- collision: a moving unit is blocked, and prediction matches the server through it ----------


func test_a_moving_hero_stops_at_an_obstacle_edge() -> void:
	var center := MapData.tower_positions(0)[0]
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var hero := sim.add_hero(0, center + Vector2(600.0, 0.0), 320.0)
	for _i in 300:
		sim.step({hero: _command(Vector2.LEFT)})  # drive straight at the obstacle
	var pos := sim.state.get_entity(hero).position
	assert_false(
		MapData.point_blocked(pos, SimCore.UNIT_RADIUS),
		"a hero driven into an obstacle never ends up inside it",
	)
	assert_gt(pos.x, center.x, "it is stopped on its approach side, not pushed through")


func test_prediction_matches_the_server_through_an_obstacle() -> void:
	# The decoded snapshot the client predicts on carries no is_hero flag, but the collision gate is
	# the same "mobile, non-creep" predicate, so the replay collides exactly as the server does.
	var start := MapData.tower_positions(0)[0] + Vector2(600.0, 0.0)
	var inputs: Array = []
	for _i in 30:
		inputs.append(_command(Vector2.LEFT))
	var acked := 15
	var server := SimCore.new()
	server.spawn_creeps = false
	var hero_id := server.add_hero(0, start, 320.0)
	for i in acked:
		server.step({hero_id: inputs[i]})
	var snapshot := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(server.state, acked))
	var predicted := snapshot.get_entity(hero_id)
	for i in range(acked, inputs.size()):
		SimCore.apply_movement(predicted, inputs[i])
	for i in range(acked, inputs.size()):
		server.step({hero_id: inputs[i]})
	assert_eq(
		predicted.position,
		server.state.get_entity(hero_id).position,
		"prediction with collision lands exactly on the authoritative position",
	)


func _command(dir: Vector2) -> InputCommand:
	var command := InputCommand.new()
	command.move_dir = dir
	return command


## Every input as a pending entry, seq stamped 1-based in send order.
func _all_pending(inputs: Array) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for i in inputs.size():
		pending.append({"seq": i + 1, "input": inputs[i]})
	return pending
