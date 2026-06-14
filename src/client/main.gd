extends Node2D
## Presentation + driver for the v0.1 match. It runs in one of three modes,
## selected from the command line (`-- --host`, `-- --join [address]`, or nothing
## for a single-machine game):
##
##   LOCAL  — owns the authoritative SimCore and drives both heroes (player + bot),
##            exactly the single-machine walking skeleton.
##   HOST   — the listen-server: owns the authoritative SimCore, drives team 0 from
##            local input, hands team 1 to a remote client when one connects (a bot
##            until then), and broadcasts a snapshot every tick.
##   CLIENT — owns no authority: it samples local input, sends it up, and draws the
##            server's snapshots — but predicts its own hero locally from that input
##            so the hero responds without a round-trip, reconciling against every
##            snapshot. Remote entities are rendered a short delay in the past,
##            interpolated between buffered snapshots, so they move smoothly through
##            network jitter and dropped packets.
##
## All authority stays in SimCore; the transport lives in NetSession; the wire
## shaping lives in NetProtocol; remote-entity smoothing lives in
## SnapshotInterpolator. This node samples input, routes it, predicts the client's
## own hero, interpolates the rest, and draws the resulting state — the same `_draw`
## serves every mode.

enum Mode { LOCAL, HOST, CLIENT }

const HERO_SPEED := 320.0
const BOT_SPEED := 300.0
const HERO_TEAM := 0
const BOT_TEAM := 1

const DEFAULT_JOIN_ADDRESS := "127.0.0.1"

## CLIENT: how far in the past (milliseconds) remote entities are rendered. The
## interpolator draws them between the snapshots bracketing this delayed time, so
## the delay is the jitter/loss budget — at the 60 Hz snapshot rate it spans ~6
## snapshots, enough that a late or dropped one is covered by its neighbours rather
## than stalling the unit. Only remote entities pay it; our own hero is predicted to
## the present, so the local player feels no added latency.
const INTERPOLATION_DELAY_MS := 100.0

const HERO_COLOR := Color(0.36, 0.66, 1.0)
const BOT_COLOR := Color(1.0, 0.42, 0.38)
const ENTITY_RADIUS := 44.0

## Creeps render as small, darkened team-coloured circles so a wave reads as a
## cluster distinct from the larger heroes.
const CREEP_RADIUS := 22.0
const CREEP_DARKEN := 0.3

## Map debug-draw styling. World-unit sizes, tuned to read at the camera's
## zoomed-out framing of the whole arena.
const FIELD_COLOR := Color(0.114, 0.125, 0.145)
const BOUNDS_COLOR := Color(0.3, 0.32, 0.36)
const BOUNDS_WIDTH := 8.0
const LANE_COLOR := Color(0.5, 0.5, 0.55, 0.7)
const LANE_WIDTH := 28.0
const CAMP_COLOR := Color(0.45, 0.7, 0.45)
const CAMP_RADIUS := 60.0
const TOWER_SIZE := Vector2(110.0, 110.0)
const NEXUS_SIZE := Vector2(200.0, 200.0)

## HP bar, drawn above any entity that carries health. Creeps get a compact bar
## scaled to their smaller footprint.
const HP_BAR_SIZE := Vector2(160.0, 26.0)
const HP_BAR_OFFSET := Vector2(-80.0, -150.0)
const CREEP_HP_BAR_SIZE := Vector2(70.0, 12.0)
const CREEP_HP_BAR_OFFSET := Vector2(-35.0, -55.0)
const HP_BAR_BG := Color(0.0, 0.0, 0.0, 0.6)
const HP_BAR_FG := Color(0.4, 0.85, 0.4)

var _mode: int = Mode.LOCAL
var _join_address := DEFAULT_JOIN_ADDRESS

## The authoritative simulation. Present in LOCAL and HOST; null on a pure CLIENT,
## which renders snapshots instead of simulating.
var _sim: SimCore = null
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0

var _net: NetSession = null
## HOST: the peer id controlling team 1, or 0 while the slot is bot-filled.
var _team1_peer: int = 0
## CLIENT: set once the server has accepted our handshake.
var _joined: bool = false
## CLIENT: the team the server assigned us; identifies our hero in a snapshot.
var _my_team: int = BOT_TEAM
## CLIENT: the world to draw — remote entities interpolated a short delay in the
## past, with our own hero overlaid at its predicted (present) position.
var _client_state: SimState = null
## CLIENT: buffers recent snapshots and renders remote entities interpolated
## between them, smoothing network jitter and dropped packets.
var _interp := SnapshotInterpolator.new()
## CLIENT: monotonic input sequence number, stamped on each input we send so the
## server can acknowledge it and we can match the ack back to a pending input.
var _input_seq: int = 0
## CLIENT: inputs sent but not yet acknowledged, oldest first, each `{seq, input}`.
## Replayed onto every snapshot to predict our hero; pruned as acks arrive.
var _pending_inputs: Array[Dictionary] = []


func _ready() -> void:
	_configure_from_cmdline()
	match _mode:
		Mode.HOST:
			_start_host()
		Mode.CLIENT:
			_start_client()
		_:
			_start_local()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	match _mode:
		Mode.HOST:
			_tick_host()
		Mode.CLIENT:
			_tick_client()
		_:
			_tick_local()
	queue_redraw()


# --- Mode setup -------------------------------------------------------------


func _configure_from_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--host":
			_mode = Mode.HOST
		elif arg == "--join":
			_mode = Mode.CLIENT
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				_join_address = args[i + 1]
				i += 1
		i += 1


func _start_local() -> void:
	_sim = SimCore.new()
	_sim.spawn_structures()
	_hero_id = _sim.add_hero(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED)
	_bot_id = _sim.add_hero(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED)


func _start_host() -> void:
	_start_local()  # the authoritative world; team 1 is bot-filled until a client takes it
	_net = _make_session()
	var err := _net.start_host()
	if err != OK:
		push_error("failed to host on port %d: error %d" % [NetSession.DEFAULT_PORT, err])
		return
	_net.client_joined.connect(_on_client_joined)
	_net.client_left.connect(_on_client_left)
	print("hosting on port %d — team 0 is local, team 1 awaits a client" % NetSession.DEFAULT_PORT)


func _start_client() -> void:
	_net = _make_session()
	var err := _net.start_client(_join_address)
	if err != OK:
		push_error("failed to join %s: error %d" % [_join_address, err])
		return
	_net.joined_server.connect(_on_joined_server)
	_net.rejected.connect(_on_rejected)
	_net.server_left.connect(_on_server_left)
	print("joining %s:%d" % [_join_address, NetSession.DEFAULT_PORT])


func _make_session() -> NetSession:
	var net := NetSession.new()
	net.name = "NetSession"
	add_child(net)
	return net


# --- Per-tick drivers -------------------------------------------------------


func _tick_local() -> void:
	_sim.step({_hero_id: _sample_player_input(), _bot_id: _bot.decide(_sim.state, _bot_id)})


func _tick_host() -> void:
	var team1_command: InputCommand
	var ack := -1
	if _team1_peer != 0:
		var remote := _net.input_for(_team1_peer)
		team1_command = remote if remote != null else InputCommand.new()
		ack = _net.input_seq_for(_team1_peer)
	else:
		team1_command = _bot.decide(_sim.state, _bot_id)
	_sim.step({_hero_id: _sample_player_input(), _bot_id: team1_command})
	_net.broadcast_snapshot(_sim.state, ack)


## Samples local input, sends it up stamped with a sequence number, buffers it as
## pending, feeds the latest snapshot to the interpolator, then rebuilds the world
## to draw. Prediction makes the local hero respond immediately instead of waiting a
## round-trip; interpolation makes the remote entities move smoothly despite jitter.
func _tick_client() -> void:
	if _joined:
		_input_seq += 1
		var command := _sample_player_input()
		_net.send_input(_input_seq, command)
		_pending_inputs.append({"seq": _input_seq, "input": command})
	_buffer_latest_snapshot()
	_client_state = _render_state()


## Feeds the freshest authoritative snapshot into the interpolation buffer. The
## interpolator ignores ticks it already holds, so polling the latest every frame is
## safe — each distinct snapshot is buffered once with its arrival time. This decodes
## its own copy; prediction decodes a separate one, so neither mutates the buffer.
func _buffer_latest_snapshot() -> void:
	var state := _net.latest_state()
	if state != null:
		_interp.push(state, Time.get_ticks_msec())


## The world to draw: remote entities interpolated INTERPOLATION_DELAY_MS in the
## past (smoothing jitter and absorbing dropped snapshots), with our own hero
## overlaid at its predicted, present-time position. Authority is never forked —
## both halves derive only from the server's snapshots. Null until the first
## snapshot arrives.
func _render_state() -> SimState:
	var state := _interp.sample(Time.get_ticks_msec() - INTERPOLATION_DELAY_MS)
	if state == null:
		return null
	_overlay_predicted_hero(state)
	return state


## Replaces our hero's interpolated (past) position in `state` with its predicted
## present-time position, so only our hero escapes the interpolation delay while
## every other entity stays smoothed.
func _overlay_predicted_hero(state: SimState) -> void:
	var predicted := _predicted_hero()
	if predicted == null:
		return
	var hero := _local_hero(state)
	if hero != null:
		hero.position = predicted.position


## Our hero reconciled against the latest snapshot: take its authoritative position,
## drop the inputs the server has already applied, and replay the rest with the same
## movement math the server runs. Authority is never forked — the snapshot rolls our
## hero back to the server's truth before the replay, so a misprediction self-corrects
## within a tick. Returns null before the first snapshot or if our hero is not in it.
func _predicted_hero() -> SimEntity:
	var state := _net.latest_state()
	if state == null:
		return null
	var hero := _local_hero(state)
	if hero == null:
		return null
	var ack := _net.latest_ack()
	while not _pending_inputs.is_empty() and _pending_inputs[0]["seq"] <= ack:
		_pending_inputs.pop_front()
	for entry in _pending_inputs:
		SimCore.apply_movement(hero, entry["input"])
	return hero


## Our hero in `state`: the one mobile, non-creep unit on our team. The walking
## skeleton seats exactly one hero per team, so the first match is ours.
func _local_hero(state: SimState) -> SimEntity:
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.team == _my_team and not entity.is_structure and not entity.is_creep:
			return entity
	return null


# --- Network event handlers -------------------------------------------------


func _on_client_joined(peer_id: int, team: int) -> void:
	_team1_peer = peer_id
	print("client connected: peer %d controls team %d" % [peer_id, team])


func _on_client_left(peer_id: int) -> void:
	if peer_id == _team1_peer:
		_team1_peer = 0
		print("client disconnected: peer %d — team 1 reverts to a bot" % peer_id)


func _on_joined_server(team: int) -> void:
	_joined = true
	_my_team = team
	print("joined the server as team %d" % team)


func _on_rejected(reason: String) -> void:
	push_error("the server refused the connection: %s" % reason)
	get_tree().quit()


func _on_server_left() -> void:
	push_error("lost the connection to the server")
	get_tree().quit()


# --- Rendering --------------------------------------------------------------


## The world this client should draw: the predicted + interpolated render state on a
## pure CLIENT, the authoritative simulation otherwise.
func _active_state() -> SimState:
	return _client_state if _mode == Mode.CLIENT else _sim.state


func _draw() -> void:
	_draw_map()
	_draw_entities()


func _draw_map() -> void:
	draw_rect(MapData.BOUNDS, FIELD_COLOR, true)
	draw_rect(MapData.BOUNDS, BOUNDS_COLOR, false, BOUNDS_WIDTH)
	for lane in MapData.lane_count():
		draw_polyline(MapData.lane_path(lane, HERO_TEAM), LANE_COLOR, LANE_WIDTH)
	for camp in MapData.JUNGLE_CAMPS:
		draw_circle(camp, CAMP_RADIUS, CAMP_COLOR)


## Draws the live world: towers and nexuses as squares, mobile units as circles,
## each with an HP bar. Structures and units share one entity list, so they all come
## from one state — the authoritative simulation in LOCAL/HOST, the predicted +
## interpolated render state on a CLIENT.
func _draw_entities() -> void:
	var state := _active_state()
	if state == null:
		return
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if entity.is_structure:
			var size := NEXUS_SIZE if entity.is_nexus else TOWER_SIZE
			draw_rect(Rect2(entity.position - size * 0.5, size), _team_color(entity.team), true)
			_draw_hp_bar(entity, HP_BAR_SIZE, HP_BAR_OFFSET)
		elif entity.is_creep:
			draw_circle(entity.position, CREEP_RADIUS, _team_color(entity.team).darkened(CREEP_DARKEN))
			_draw_hp_bar(entity, CREEP_HP_BAR_SIZE, CREEP_HP_BAR_OFFSET)
		else:
			draw_circle(entity.position, ENTITY_RADIUS, _team_color(entity.team))
			_draw_hp_bar(entity, HP_BAR_SIZE, HP_BAR_OFFSET)


func _draw_hp_bar(entity: SimEntity, size: Vector2, offset: Vector2) -> void:
	if entity.max_hp <= 0:
		return
	var frac := clampf(float(entity.hp) / float(entity.max_hp), 0.0, 1.0)
	var top_left := entity.position + offset
	draw_rect(Rect2(top_left, size), HP_BAR_BG, true)
	draw_rect(Rect2(top_left, Vector2(size.x * frac, size.y)), HP_BAR_FG, true)


func _team_color(team: int) -> Color:
	return HERO_COLOR if team == HERO_TEAM else BOT_COLOR


func _sample_player_input() -> InputCommand:
	var command := InputCommand.new()
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	command.move_dir = dir
	return command
