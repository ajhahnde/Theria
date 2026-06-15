extends Node2D
## Presentation + driver for the v0.1 match. It runs in one of three modes. A
## windowed launch with no mode flag opens a connect menu to pick one; the command
## line selects one directly (`-- --host`, `-- --join [address]`, `-- --local`); and
## a headless launch with no flag defaults to LOCAL, so the automated smokes need no
## menu and stay flag-driven:
##
##   LOCAL  — owns the authoritative SimCore and fields a full Solane squad per
##            team: the player drives one hero (picked with `--hero`), every other
##            seat is bot-driven. The single-machine practice match.
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
## A CLIENT may add `--netsim <latency>,<jitter>,<loss>` to shape its incoming
## snapshot stream as if it had crossed a worse link — a debug aid for watching the
## adaptive interpolation delay grow and the interpolation cover dropped snapshots,
## since the local machine and LAN deliver almost perfectly.
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

## Fixed seed for the optional `--netsim` conditioner, so a shaped playtest replays
## the same drop and jitter pattern run to run.
const NETSIM_SEED := 1

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

## The Volk the player's team falls back to in a LOCAL practice match when `--hero`
## names no known hero. The rosters themselves live in `AbilityData.VOLK` — the single
## source of which heroes form which Volk — and `_start_local` seats the player's chosen
## Volk against the opposing one, so the match exercises both rosters and all four
## targeting modes. HOST/CLIENT still seat the one-per-team duel (DUEL_KIT below): the
## wire identifies a hero by its team, so a networked squad waits on the protocol step
## that gives each client a controlled-entity id.
const DEFAULT_VOLK := "solane"

## The kit both heroes mirror in a HOST/CLIENT duel — the one-per-team walking
## skeleton the netcode is built around until the multi-hero wire step lands.
const DUEL_KIT := "lion"

## Ability bar keys, one per slot (0..3). Movement owns WASD/arrows, so the four
## abilities sit on the number row rather than QWER. A held key recasts the slot as
## soon as its cooldown and resource allow (quick-cast).
const ABILITY_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]

## Resource bar, drawn just under a hero's HP bar, and the form ring around a hero —
## white while human, amber while shifted to the animal form.
const RES_BAR_SIZE := Vector2(160.0, 14.0)
const RES_BAR_OFFSET := Vector2(-80.0, -118.0)
const RES_BAR_BG := Color(0.0, 0.0, 0.0, 0.6)
const RES_BAR_FG := Color(0.35, 0.6, 0.95)
const FORM_RING_WIDTH := 6.0
const FORM_RING_GAP := 6.0
const HUMAN_RING_COLOR := Color(0.95, 0.95, 0.95)
const ANIMAL_RING_COLOR := Color(1.0, 0.62, 0.2)

var _mode: int = Mode.LOCAL
var _join_address := DEFAULT_JOIN_ADDRESS

## True once a mode flag (`--host`/`--join`/`--local`) was passed, so a flagged or
## headless launch enters the match directly and a bare windowed launch shows the menu.
var _explicit_mode := false
## The connect-menu overlay while it is up; freed once a mode is chosen. Null on a
## flagged or headless launch (the menu never opens) and after the match begins.
var _menu_layer: CanvasLayer = null
## False until a mode has started; gates the per-tick driver and entity draw so the
## menu can sit over a static backdrop with no simulation running behind it.
var _started := false

## CLIENT: optional simulated link conditions parsed from `--netsim
## <latency>,<jitter>,<loss>`, as `[latency_ms, jitter_ms, loss]`, or empty to take
## snapshots as they arrive. A debug aid for exercising the smoothing under a worse
## link than the local machine provides.
var _netsim_params: Array = []

## The authoritative simulation. Present in LOCAL and HOST; null on a pure CLIENT,
## which renders snapshots instead of simulating.
var _sim: SimCore = null
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0

## LOCAL: the hero the player drives, from `--hero` — any hero of either Volk. Its
## Volk fills the player's team and the opposing Volk the bot team, so the choice also
## picks the match-up. Falls back to the first hero of the default Volk if unset or
## unrecognised. Ignored by HOST/CLIENT, which seat the duel.
var _player_hero: String = AbilityData.VOLK[DEFAULT_VOLK][0]
## LOCAL: every bot-driven hero this match — the player's two squadmates and the
## three opponents — each stepped from its own BotController decision.
var _bot_ids: Array[int] = []

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
	if _explicit_mode or _is_headless():
		_enter_match()
	else:
		_open_connect_menu()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _started:
		return
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
			_explicit_mode = true
		elif arg == "--join":
			_mode = Mode.CLIENT
			_explicit_mode = true
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				_join_address = args[i + 1]
				i += 1
		elif arg == "--local":
			_mode = Mode.LOCAL
			_explicit_mode = true
		elif arg == "--hero":
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				_player_hero = args[i + 1]
				i += 1
		elif arg == "--netsim":
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				_netsim_params = _parse_netsim(args[i + 1])
				i += 1
		i += 1


## Parses a `--netsim` value of `latency,jitter,loss` (milliseconds, milliseconds,
## a 0..1 fraction) into `[latency_ms, jitter_ms, loss]`. Missing trailing fields
## default to zero; a malformed value yields an empty array (the conditioner is left
## off) with a warning, so a typo degrades to a normal join rather than a crash.
func _parse_netsim(value: String) -> Array:
	var fields := value.split(",")
	var nums: Array = []
	for field in fields:
		if not field.is_valid_float():
			push_warning("ignoring malformed --netsim value %s (want latency,jitter,loss)" % value)
			return []
		nums.append(field.to_float())
	return [
		maxf(0.0, (nums[0] if nums.size() > 0 else 0.0)),
		maxf(0.0, (nums[1] if nums.size() > 1 else 0.0)),
		clampf((nums[2] if nums.size() > 2 else 0.0), 0.0, 1.0),
	]


## Dispatches to the selected mode and marks the match live, so the per-tick driver
## and entity draw begin. The single entry point for both the command-line path and a
## menu choice.
func _enter_match() -> void:
	match _mode:
		Mode.HOST:
			_start_host()
		Mode.CLIENT:
			_start_client()
		_:
			_start_local()
	_started = true
	queue_redraw()


## A headless run cannot drive a menu (no display, no pointer), so it always takes a
## mode from the command line — defaulting to LOCAL — and never opens the connect
## screen. This keeps the automated smokes flag-driven and non-interactive.
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Opens the connect menu over a static map backdrop and waits: the match begins only
## once the player picks a mode. Built in code on its own CanvasLayer so it renders in
## screen space, above the world the zoomed game camera draws.
func _open_connect_menu() -> void:
	var menu := ConnectMenu.new()
	menu.default_address = DEFAULT_JOIN_ADDRESS
	menu.practice_requested.connect(_on_practice_requested)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	_menu_layer = CanvasLayer.new()
	_menu_layer.add_child(menu)
	add_child(_menu_layer)


func _on_practice_requested() -> void:
	_mode = Mode.LOCAL
	_close_menu_and_enter()


func _on_host_requested() -> void:
	_mode = Mode.HOST
	_close_menu_and_enter()


func _on_join_requested(address: String) -> void:
	_mode = Mode.CLIENT
	_join_address = address
	_close_menu_and_enter()


## Tears down the connect overlay and enters the chosen match. Shared by every menu
## choice so the menu always leaves the tree exactly once, before the match runs.
func _close_menu_and_enter() -> void:
	if _menu_layer != null:
		_menu_layer.queue_free()
		_menu_layer = null
	_enter_match()


## Practice: a Volk-vs-Volk match. `--hero` names the hero the player drives; that
## hero's Volk (per `AbilityData.VOLK`) fills the player's team and the opposing Volk the
## bot team, one hero per roster kit. The player drives the matching seat; the other five
## are bot-driven, so both rosters are on the field at once. An unknown name falls back
## to the default Volk's first hero, so a typo starts a valid match instead of crashing.
func _start_local() -> void:
	_sim = _new_world()
	var player_volk := AbilityData.volk_of(_player_hero)
	if player_volk == "":
		var fallback: String = AbilityData.VOLK[DEFAULT_VOLK][0]
		push_warning("unknown --hero %s; defaulting to %s" % [_player_hero, fallback])
		_player_hero = fallback
		player_volk = DEFAULT_VOLK
	var player_roster: Array[String] = []
	player_roster.assign(AbilityData.VOLK[player_volk])
	var bot_roster: Array[String] = []
	bot_roster.assign(AbilityData.VOLK[AbilityData.opposing_volk(player_volk)])
	_seat_squad(HERO_TEAM, HERO_SPEED, player_roster, player_roster.find(_player_hero))
	_seat_squad(BOT_TEAM, BOT_SPEED, bot_roster, -1)


## Seats one hero per kit in `roster` for `team`, each fanned across the base fountain
## and equipped with its kit. The seat at `player_slot` becomes the player's hero
## (`_hero_id`); every other seat is bot-driven (appended to `_bot_ids`). A
## `player_slot` of -1 leaves the whole team bot-driven.
func _seat_squad(team: int, speed: float, roster: Array[String], player_slot: int) -> void:
	for i in roster.size():
		var id := _sim.add_hero(team, MapData.squad_spawn(team, i, roster.size()), speed)
		_sim.equip_kit(id, roster[i])
		if i == player_slot:
			_hero_id = id
		else:
			_bot_ids.append(id)


## The HOST/CLIENT walking skeleton: exactly one hero per team, both mirroring the
## duel kit. The wire identifies a hero by its team, so this one-per-team seating is
## what the netcode — prediction, interpolation, snapshot identity — is built
## around; the LOCAL squad stays off the wire until that protocol step lands.
func _seat_duel() -> void:
	_sim = _new_world()
	_hero_id = _sim.add_hero(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED)
	_bot_id = _sim.add_hero(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED)
	# Both heroes carry the kit so the match starts mirror-fair; the bot drives
	# movement only (no casts yet) but shows its form and resource.
	_sim.equip_kit(_hero_id, DUEL_KIT)
	_sim.equip_kit(_bot_id, DUEL_KIT)


## A fresh authoritative world with its structures spawned, shared by both the
## LOCAL squad and the HOST/CLIENT duel seating.
func _new_world() -> SimCore:
	var sim := SimCore.new()
	sim.spawn_structures()
	return sim


func _start_host() -> void:
	_seat_duel()  # the authoritative world; team 1 is bot-filled until a client takes it
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
	if not _netsim_params.is_empty():
		_net.configure_netsim(_netsim_params[0], _netsim_params[1], _netsim_params[2], NETSIM_SEED)
		print(
			"simulating link: %d ms latency, %d ms jitter, %d%% loss"
			% [_netsim_params[0], _netsim_params[1], roundi(_netsim_params[2] * 100.0)]
		)
	print("joining %s:%d" % [_join_address, NetSession.DEFAULT_PORT])


func _make_session() -> NetSession:
	var net := NetSession.new()
	net.name = "NetSession"
	add_child(net)
	return net


# --- Per-tick drivers -------------------------------------------------------


func _tick_local() -> void:
	var inputs := {_hero_id: _sample_player_input()}
	for id in _bot_ids:
		inputs[id] = _bot.decide(_sim.state, id)
	_sim.step(inputs)


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
	_buffer_snapshots()
	_client_state = _render_state()


## Feeds freshly arrived authoritative snapshots into the interpolation buffer. With
## a `--netsim` conditioner the session releases the snapshots whose simulated delay
## has elapsed, each stamped with its release time so the injected latency and jitter
## read as real arrival timing; otherwise the freshest snapshot is buffered as it
## stands. Either way the interpolator ignores ticks it already holds, so each
## distinct snapshot is buffered once. This decodes its own copy; prediction decodes
## a separate one, so neither mutates the buffer.
func _buffer_snapshots() -> void:
	var now := float(Time.get_ticks_msec())
	if _net.is_conditioned():
		for delivered in _net.drain_snapshots(now):
			_interp.push(delivered["state"], delivered["time"])
	else:
		var state := _net.latest_state()
		if state != null:
			_interp.push(state, now)


## The world to draw: remote entities interpolated in the past (smoothing jitter and
## absorbing dropped snapshots), with our own hero overlaid at its predicted,
## present-time position. The interpolation delay adapts to the live connection's
## jitter. Authority is never forked — both halves derive only from the server's
## snapshots. Null until the first snapshot arrives.
func _render_state() -> SimState:
	var state := _interp.sample(Time.get_ticks_msec() - _interp.target_delay_ms())
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
	if _started:
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
			if entity.is_hero:
				_draw_form_ring(entity)
				_draw_resource_bar(entity)


func _draw_hp_bar(entity: SimEntity, size: Vector2, offset: Vector2) -> void:
	if entity.max_hp <= 0:
		return
	var frac := clampf(float(entity.hp) / float(entity.max_hp), 0.0, 1.0)
	var top_left := entity.position + offset
	draw_rect(Rect2(top_left, size), HP_BAR_BG, true)
	draw_rect(Rect2(top_left, Vector2(size.x * frac, size.y)), HP_BAR_FG, true)


## A ring around a hero whose colour reads its active shapeshifter form — white
## while human, amber once shifted to the animal form. Drawn just outside the hero
## circle so it never hides the team colour.
func _draw_form_ring(entity: SimEntity) -> void:
	var color := ANIMAL_RING_COLOR if entity.form == AbilitySpec.FORM_ANIMAL else HUMAN_RING_COLOR
	draw_arc(entity.position, ENTITY_RADIUS + FORM_RING_GAP, 0.0, TAU, 48, color, FORM_RING_WIDTH)


## A hero's resource pool as a bar under its HP bar. Nothing is drawn for an entity
## with no pool (an unequipped hero, or a snapshot-decoded one — the resource is not
## carried over the wire).
func _draw_resource_bar(entity: SimEntity) -> void:
	if entity.resource_max <= 0:
		return
	var frac := clampf(float(entity.resource) / float(entity.resource_max), 0.0, 1.0)
	var top_left := entity.position + RES_BAR_OFFSET
	draw_rect(Rect2(top_left, RES_BAR_SIZE), RES_BAR_BG, true)
	draw_rect(Rect2(top_left, Vector2(RES_BAR_SIZE.x * frac, RES_BAR_SIZE.y)), RES_BAR_FG, true)


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
	_sample_ability(command)
	return command


## Layers ability-cast intent onto a movement command. Only with a local
## authoritative simulation (LOCAL/HOST): a pure CLIENT samples no abilities, since
## the wire carries movement alone and networked casting is a later, protocol-
## versioned step. The pressed slot keys the cast; the cursor is the aim point a
## skillshot or ground ability uses, and the enemy nearest the cursor is the lock a
## unit-targeted ability uses — the simulation reads whichever the cast ability needs.
func _sample_ability(command: InputCommand) -> void:
	if _sim == null:
		return
	var slot := _pressed_ability_slot()
	if slot < 0:
		return
	var aim := get_global_mouse_position()
	command.ability_slot = slot
	command.target_point = aim
	command.target_id = AbilityExecutor.pick_unit_target(_sim.state, HERO_TEAM, aim)


## The bar slot of the first held ability key (0..3), or -1 if none is down.
func _pressed_ability_slot() -> int:
	for slot in ABILITY_KEYS.size():
		if Input.is_physical_key_pressed(ABILITY_KEYS[slot]):
			return slot
	return -1
