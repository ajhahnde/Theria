extends Node3D
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
##            server's snapshots — but predicts its own hero locally from that input so it
##            responds without a round-trip, reconciling against every snapshot. Remote
##            entities render a short delay in the past, interpolated between buffered
##            snapshots, so they move smoothly through jitter and dropped packets. A
##            `--netsim <latency>,<jitter>,<loss>` shapes the incoming stream to debug this.
##
## Authority stays in SimCore; transport in NetSession; wire shaping in NetProtocol;
## remote-entity smoothing in SnapshotInterpolator. This node samples input, routes it,
## predicts the client's own hero, interpolates the rest, and presents the result.
##
## Presentation is 2.5D: the sim stays a flat 2D world (`Vector2`) and the client renders it
## under a pitched `Camera3D` following the hero — a sim point `Vector2(x, y)` maps to
## `Vector3(x, 0, y)` on the ground. Every entity owns a pooled 3D view (mesh + billboarded
## bars + status label) reconciled against the live state each tick. The wire is untouched —
## a pure presentation layer over the same 2D state every mode produces.

enum Mode { LOCAL, HOST, CLIENT }

const HERO_SPEED := 215.0
const BOT_SPEED := 200.0
const HERO_TEAM := 0
const BOT_TEAM := 1

const DEFAULT_JOIN_ADDRESS := "127.0.0.1"

## Fixed seed for the optional `--netsim` conditioner, so a shaped playtest replays
## the same drop and jitter pattern run to run.
const NETSIM_SEED := 1

# --- Presentation (2.5D) ----------------------------------------------------
# The sim is a flat 2D world rendered under a pitched Camera3D, Vector2(x, y) at
# Vector3(x, 0, y). Sizes are world units, 1:1 with the sim so the mouse-ray needs no rescale.

const HERO_COLOR := Color(0.36, 0.66, 1.0)
const BOT_COLOR := Color(1.0, 0.42, 0.38)

## Hero body: a standing capsule of this radius and height. CREEP_* is the smaller body a
## wave member gets, so a wave reads as a cluster apart from the heroes.
const ENTITY_RADIUS := 44.0
const HERO_BODY_HEIGHT := 150.0
const CREEP_RADIUS := 31.0
const CREEP_BODY_HEIGHT := 80.0
const CREEP_DARKEN := 0.3

## Per-hero tint: a team's heroes share its base colour, each shaded by its roster seat (0..2)
## so squadmates read apart while the team hue stays. Indexed by `AbilityData.roster_index`;
## positive lightens, negative darkens; no seat (unknown kit) keeps the flat team colour.
const HERO_SHADES: Array[float] = [0.0, 0.28, -0.22]

## Structures stand as boxes on the ground: a square footprint (tower/nexus) extruded
## up by STRUCTURE_HEIGHT.
const TOWER_SIZE := 110.0
const NEXUS_SIZE := 200.0
const STRUCTURE_HEIGHT := 220.0

## Ground + lighting. The ground plane wears a jungle short-grass shader (GROUND_SHADER —
## toon-banded patches of two greens); behind it the sky is a dark jungle backdrop. The key
## light and ambient fill are tuned so the cel-banded units and ground read with depth
## rather than as flat dots.
const GROUND_SHADER: Shader = preload("res://src/client/ground.gdshader")
const BACKDROP_COLOR := Color(0.06, 0.12, 0.09)
const AMBIENT_COLOR := Color(0.52, 0.56, 0.64)
const AMBIENT_ENERGY := 0.5
const LIGHT_ENERGY := 1.1

## Billboarded HP/resource bars + status label floating above a unit (world units). Every
## body's HP bar floats HERO_BAR_GAP above its own model's measured top (animals, creeps, and
## structures all vary in height), the resource bar a step below and the status label above.
const BAR_WIDTH := 170.0
const BAR_HEIGHT := 24.0
const HERO_BAR_GAP := 70.0
const RES_BAR_DROP := 36.0
const STATUS_LABEL_RISE := 70.0
const HP_BAR_BG := Color(0.0, 0.0, 0.0, 0.55)
const HP_BAR_FG := Color(0.4, 0.85, 0.4)
const RES_BAR_FG := Color(0.35, 0.6, 0.95)
const STATUS_FONT_SIZE := 120

## The tribe the player's team falls back to in a LOCAL practice match when `--hero` names no
## known hero. Rosters live in `AbilityData.TRIBE`; `_start_local` seats the chosen tribe
## against the opposing one. HOST/CLIENT still seat the one-per-team duel (DUEL_KIT below)
## until the protocol step that gives each client a controlled-entity id lands.
const DEFAULT_TRIBE := "solane"

## The kit both heroes mirror in a HOST/CLIENT duel — the one-per-team walking
## skeleton the netcode is built around until the multi-hero wire step lands.
const DUEL_KIT := "lion"

## Form ring laid flat on the ground under a hero, reading its active shapeshifter
## form — white while human, amber while shifted to the animal form.
const FORM_RING_RADIUS := 70.0
const FORM_RING_THICKNESS := 12.0
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

## Samples the local player's mouse/keys into an InputCommand and owns the move/attack order
## state (right-click to move or attack, QWER to cast). Built once the camera exists.
var _player_input: PlayerInput = null
## The on-ground marker drawn at the active move target while the hero walks to it.
var _move_marker: MoveMarker = null

## LOCAL: the hero the player drives, from `--hero` — any hero of either tribe. Its
## tribe fills the player's team and the opposing tribe the bot team, so the choice also
## picks the match-up. Falls back to the first hero of the default tribe if unset or
## unrecognised. Ignored by HOST/CLIENT, which seat the duel.
var _player_hero: String = AbilityData.TRIBE[DEFAULT_TRIBE][0]
## The bot skill level, from `--bot-difficulty` or the menu, applied to `_bot` when the
## match begins. Defaults to "easy" so practice is winnable out of the box; "normal" and
## "hard" sharpen the bots' reaction. Held as a name and resolved to a level at apply.
var _bot_difficulty: String = "easy"
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

## Presentation: the follow-camera, the ground plane, and the per-entity view pool.
## Each view holds the node refs `_update_view` mutates — `{root, body, ring?, hp_node,
## hp_fg, res_node?, res_fg?, status?}` — so a unit's nodes are built once, never rebuilt
## while it lives. Filled in `_build_world` / `_sync_world`; see the presentation region.
## The follow-rig — the Camera3D, its eased target, and the free-look state — lifted into its own
## class to keep this file under the line cap. Built in `_build_world`, trailed each tick.
var _cam: MatchCamera = null
var _ground: MeshInstance3D = null
## The shared map-decor material (JungleDecor); fed the hero's world position each frame so the
## growth over the player's hero fades and the character stays visible.
var _foliage_mat: ShaderMaterial = null
var _views: Dictionary = {}
## The match's screen-space UI — the hero HUD, the kill feed, the chat box, and the death
## screen — built and driven as one layer by `MatchOverlays`, reconciled each tick in
## `_sync_world`. Null on a headless run (no display to draw it on).
var _overlays: MatchOverlays = null
## The fog-of-war sheet over the playfield, fed the player team's reveal circles each tick in
## `_sync_world`. Null on a headless run (no display to draw it on).
var _fog: FogOverlay = null


func _ready() -> void:
	_build_world()
	_configure_from_cmdline()
	if _explicit_mode or _is_headless():
		_enter_match()
	else:
		_open_connect_menu()


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
	_sync_world()


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
		elif arg == "--bot-difficulty":
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				_set_bot_difficulty(args[i + 1])
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


## Records the bot skill level from a `--bot-difficulty` value (or the menu), keeping it
## only when it names a known level so a typo degrades to the current default with a
## warning rather than starting an unintended difficulty.
func _set_bot_difficulty(level_name: String) -> void:
	if BotController.DIFFICULTY_NAMES.has(level_name):
		_bot_difficulty = level_name
	else:
		push_warning("unknown --bot-difficulty %s; keeping %s (want easy|normal|hard)" % [
			level_name, _bot_difficulty
		])


## Dispatches to the selected mode and marks the match live, so the per-tick driver
## and entity draw begin. The single entry point for both the command-line path and a
## menu choice.
func _enter_match() -> void:
	_bot.difficulty = BotController.difficulty_from_name(_bot_difficulty)
	match _mode:
		Mode.HOST:
			_start_host()
		Mode.CLIENT:
			_start_client()
		_:
			_start_local()
	_started = true


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
	menu.default_hero = _player_hero
	menu.default_difficulty = _bot_difficulty
	menu.practice_requested.connect(_on_practice_requested)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	_menu_layer = CanvasLayer.new()
	_menu_layer.add_child(menu)
	add_child(_menu_layer)


## The menu's Practice choice carries the hero the player picked and the bot difficulty;
## both override any `--hero` / `--bot-difficulty` parsed from the command line. The hero's
## tribe fields the player's team and the opposing tribe the bots, so the pick also chooses
## the match-up.
func _on_practice_requested(hero: String, difficulty: String) -> void:
	_mode = Mode.LOCAL
	_player_hero = hero
	_set_bot_difficulty(difficulty)
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


## Practice: a tribe-vs-tribe match. `--hero` names the hero the player drives; that
## hero's tribe (per `AbilityData.TRIBE`) fills the player's team and the opposing tribe the
## bot team, one hero per roster kit. The player drives the matching seat; the other five
## are bot-driven, so both rosters are on the field at once. An unknown name falls back
## to the default tribe's first hero, so a typo starts a valid match instead of crashing.
func _start_local() -> void:
	_sim = _new_world()
	var player_tribe := AbilityData.tribe_of(_player_hero)
	if player_tribe == "":
		var fallback: String = AbilityData.TRIBE[DEFAULT_TRIBE][0]
		push_warning("unknown --hero %s; defaulting to %s" % [_player_hero, fallback])
		_player_hero = fallback
		player_tribe = DEFAULT_TRIBE
	var player_roster: Array[String] = []
	player_roster.assign(AbilityData.TRIBE[player_tribe])
	var bot_roster: Array[String] = []
	bot_roster.assign(AbilityData.TRIBE[AbilityData.opposing_tribe(player_tribe)])
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
	# Fog of war: the client only ever receives what its team (the remote team) can see, so an
	# enemy in fog never crosses the wire — the filter is authoritative, not a render dim.
	_net.broadcast_snapshot(_sim.state, ack, Vision.visible_ids(_sim.state, NetSession.REMOTE_TEAM))


## Samples local input, sends it up stamped with a sequence number, buffers it as pending,
## feeds the latest snapshot to the interpolator, then rebuilds the world to draw. Prediction
## makes the local hero respond without a round-trip; interpolation smooths the rest.
func _tick_client() -> void:
	if _joined:
		_input_seq += 1
		var command := _sample_player_input()
		_net.send_input(_input_seq, command)
		_pending_inputs.append({"seq": _input_seq, "input": command})
	_buffer_snapshots()
	_client_state = _render_state()


## Feeds freshly arrived authoritative snapshots into the interpolation buffer. With a
## `--netsim` conditioner the session releases snapshots whose simulated delay has elapsed,
## stamped with their release time so injected latency/jitter read as real arrival timing;
## otherwise the freshest is buffered as it stands. The interpolator ignores ticks it already
## holds, so each distinct snapshot is buffered once, from its own decoded copy.
func _buffer_snapshots() -> void:
	var now := float(Time.get_ticks_msec())
	if _net.is_conditioned():
		for delivered in _net.drain_snapshots(now):
			_interp.push(delivered["state"], delivered["time"])
	else:
		var state := _net.latest_state()
		if state != null:
			_interp.push(state, now)


## The world to draw: remote entities interpolated in the past (smoothing jitter, absorbing
## dropped snapshots, delay adapting to the live link), with our own hero overlaid at its
## predicted present-time position. Both halves derive only from the server's snapshots —
## authority is never forked. Null until the first snapshot arrives.
func _render_state() -> SimState:
	var state := _interp.sample(Time.get_ticks_msec() - _interp.target_delay_ms())
	if state == null:
		return null
	_overlay_predicted_hero(state)
	return state


## Replaces our hero's interpolated (past) position in `state` with its predicted present-time
## position, so only our hero escapes the interpolation delay while everything else stays smoothed.
func _overlay_predicted_hero(state: SimState) -> void:
	var predicted := _predicted_hero()
	if predicted == null:
		return
	var hero := _local_hero(state)
	if hero != null:
		hero.position = predicted.position


## Our hero reconciled against the latest snapshot: take its authoritative position, drop the
## inputs the server has already applied, and replay the rest with the server's movement math.
## The snapshot rolls our hero back to the server's truth before the replay, so a misprediction
## self-corrects within a tick. Null before the first snapshot or if our hero is not in it.
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


## Our hero in `state`: the one mobile, non-creep unit on our team (one hero per team today).
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


# --- Presentation: 3D world + view pool -------------------------------------
# A sim point on the 2D field, Vector2(x, y), sits at Vector3(x, 0, y) on the ground.
# Each entity owns a pooled view (`_views[id]`), reconciled against the live state.


## A sim point on the 2D field, placed on the 3D ground: Vector2(x, y) -> (x, 0, y).
func _world(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## A sim point placed on the rolling terrain: the flat-ground point lifted by the hill height under
## it, so a unit's view walks over a mound instead of clipping through it. The sim stays flat — its
## collision and pathing are 2D on Y = 0; only the rendered node rides the relief. Used for unit
## roots — the camera, ground plane, marker, and canopy fade stay flat.
func _ground_at(p: Vector2) -> Vector3:
	return _world(p) + Vector3(0.0, JungleDecor.height_at(p), 0.0)


## Builds the static 3D scene once: a ground plane spanning the arena, a key light and
## an ambient fill so the primitives read with depth, and the follow-camera framing the
## arena centre to start. Authored in code (not the .tscn) so the scene file stays a
## bare root and the Godot editor — which rewrites project.godot — is never needed.
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, -45.0, 0.0)
	light.light_energy = LIGHT_ENERGY
	add_child(light)
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = MapData.BOUNDS.size
	_ground.mesh = plane
	_ground.position = _world(MapData.BOUNDS.get_center())
	_ground.material_override = _ground_material()
	add_child(_ground)
	MapView.build(self)
	_foliage_mat = JungleDecor.build(self)
	_cam = MatchCamera.new(Callable(self, "_world"))
	add_child(_cam.node)
	_cam.place(MapData.BOUNDS.get_center())
	_player_input = PlayerInput.new(_cam.node)
	_move_marker = MoveMarker.new()
	add_child(_move_marker)
	# The screen-space UI (HUD, kill feed, chat, death screen) draws over the zoomed game camera,
	# exactly like the connect menu. MatchOverlays owns its canvas layers; a headless smoke has no
	# display to raise it on, so it is built only with one.
	if not _is_headless():
		_overlays = MatchOverlays.new()
		add_child(_overlays)
		# The minimap projects a click back to a world point and emits it; wire one to the player's
		# order pipeline and one to the camera pan, so the panel itself owns no game state.
		_overlays.minimap.order_requested.connect(_on_minimap_order)
		_overlays.minimap.look_requested.connect(_on_minimap_look)
		_fog = FogOverlay.build(self)


## Reconciles the view pool against the live state, then trails the camera. Called each
## tick after the mode's step: a view is spawned the first time its entity is seen,
## updated while it persists, and freed once its id leaves the state (a dead unit).
func _sync_world() -> void:
	var state := _active_state()
	if state == null:
		return
	for id in state.entities:
		var entity: SimEntity = state.entities[id]
		if not _views.has(id):
			_views[id] = _make_view(entity)
		_update_view(_views[id], entity)
	for id in _views.keys():
		if not state.entities.has(id):
			(_views[id]["root"] as Node3D).queue_free()
			_views.erase(id)
	if _fog != null:
		# Fog of war: dim the unseen ground and hide enemies in it. A pure CLIENT's snapshot is
		# already filtered to its team, so only a local-authority world needs the enemy-hiding pass.
		_fog.apply(state, _player_team(), _views, _mode != Mode.CLIENT)
	for event in state.fx_events:
		MatchFx.play(self, event)
	for attack in state.attack_events:
		CombatFx.strike(self, attack)
	for hit in state.hit_events:
		CombatFx.number(self, hit)
	if _player_input.has_move_target:
		_move_marker.point_at(_player_input.move_target)
	else:
		_move_marker.clear()
	_follow_camera(state)
	_update_overlays(state)


## Trails the camera on the player's hero — re-pinned to it each tick it exists, held at its last
## sighting while it is gone (dead, pre-spawn), unless free-look holds a minimap-panned point that
## the re-centre key (SPACE, ignored while typing) drops. MatchCamera owns the easing; this hands it
## the hero's point and feeds the map decor the framed spot so growth over it fades to its outline.
func _follow_camera(state: SimState) -> void:
	var hero := _camera_focus(state)
	var recenter := Input.is_physical_key_pressed(KEY_SPACE) and not _chat_typing()
	_cam.follow(hero.position if hero != null else Vector2.ZERO, hero != null, recenter)
	if _foliage_mat != null:
		_foliage_mat.set_shader_parameter("hero_pos", _world(_cam.target()))


## The unit the camera trails: the player's own hero. LOCAL drives `_hero_id`; a CLIENT
## reads its team's hero out of the render state; either way null before one exists.
func _camera_focus(state: SimState) -> SimEntity:
	if _mode == Mode.CLIENT:
		return _local_hero(state)
	if state.entities.has(_hero_id):
		return state.entities[_hero_id]
	return null


## A right-click on the minimap: issue the player's move/attack order at that world point, through
## the same pipeline a world right-click uses, so it auto-paths and reconciles over the wire.
func _on_minimap_order(point: Vector2) -> void:
	_player_input.order_at(_visible_state(), _player_hero_entity(), _player_team(), point)


## A left-click (or left-drag) on the minimap: pan the camera there for a free look, holding it off
## the hero until the player re-centres.
func _on_minimap_look(point: Vector2) -> void:
	_cam.look_at_point(point)


## Reconciles the whole screen-space UI each tick: the HUD, kill feed, and death screen all
## read off the player's focus hero (the camera's hero — sim-driven in LOCAL/HOST, read out of
## the snapshot on a CLIENT), so every overlay shows exactly what the player is driving. The
## kill feed also takes the two team colours for its lines.
func _update_overlays(state: SimState) -> void:
	if _overlays == null:
		return
	_overlays.update(
		_camera_focus(state), state, _player_team(), [HERO_COLOR, BOT_COLOR],
		SimCore.TICK_RATE, _mode != Mode.CLIENT,
	)


## Whether the player is typing in chat — the driver suppresses ability casts while they are, so
## the letters of a message never fire the QWER bar. Movement (a mouse click) is left alone.
func _chat_typing() -> bool:
	return _overlays != null and _overlays.is_chat_typing()


## Builds an entity's pooled view: a primitive body (capsule unit, box structure), a
## flat ground ring for heroes, and a billboarded overlay carrying the HP bar, the
## resource bar (heroes), and the status label (heroes). Returns the node refs the
## per-tick update mutates, so nothing is rebuilt while the entity lives.
func _make_view(entity: SimEntity) -> Dictionary:
	var root := Node3D.new()
	root.position = _ground_at(entity.position)
	add_child(root)
	var view := {"root": root}
	view["body"] = _build_body(root, entity)
	if entity.is_hero and HeroModelLibrary.has_model(entity.kit_id):
		HeroModelLibrary.setup_facing(view, entity.kit_id, view["body"])
	HeroModelLibrary.add_shadow(root, view["body"])
	if entity.is_hero:
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh()
		ring.position = Vector3(0.0, HeroModelLibrary.SHADOW_Y + 1.0, 0.0)  # over the shadow blob
		ring.material_override = _flat_material(HUMAN_RING_COLOR)
		root.add_child(ring)
		view["ring"] = ring
	_attach_overlay(view, entity)
	return view


## Builds an entity's body under `root`: a size-normalised model — the hero's animal (by
## kit), a structure's tower/nexus, or a lane creep's slime — handed off to
## HeroModelLibrary, which stands it on the ground at its on-field size and washes it with
## the team colour. Returned so the view can hold it, though the body is never mutated
## again once built — team and form read off the tint and the ring, not the body. Only a
## pure CLIENT hero whose snapshot carried no `kit_id` falls through to the capsule, so an
## unmodelled hero still draws.
func _build_body(root: Node3D, entity: SimEntity) -> Node3D:
	if entity.is_hero and HeroModelLibrary.has_model(entity.kit_id):
		return HeroModelLibrary.add_to(root, entity.kit_id, _team_color(entity.team))
	if entity.is_structure:
		var prop := "nexus" if entity.is_nexus else "tower"
		return HeroModelLibrary.add_prop(root, prop, _team_color(entity.team))
	if entity.is_creep:
		return HeroModelLibrary.add_prop(root, "creep", _team_color(entity.team).darkened(CREEP_DARKEN))
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh(entity)
	body.position = Vector3(0.0, _body_half_height(entity), 0.0)
	body.material_override = _flat_material(_body_color(entity))
	root.add_child(body)
	return body


## Hangs the floating UI above an entity: an HP bar for anything with health, plus a
## resource bar and a status label for a hero. Creeps get only a lower HP bar.
func _attach_overlay(view: Dictionary, entity: SimEntity) -> void:
	var root: Node3D = view["root"]
	var hp_y := _hp_bar_y(view["body"])
	var hp := _make_bar(HP_BAR_FG, hp_y)
	root.add_child(hp["node"])
	view["hp_node"] = hp["node"]
	view["hp_fg"] = hp["fg"]
	if not entity.is_hero:
		return
	var res := _make_bar(RES_BAR_FG, hp_y - RES_BAR_DROP)
	root.add_child(res["node"])
	view["res_node"] = res["node"]
	view["res_fg"] = res["fg"]
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = STATUS_FONT_SIZE
	label.outline_size = STATUS_FONT_SIZE / 6
	label.position = Vector3(0.0, hp_y + STATUS_LABEL_RISE, 0.0)
	root.add_child(label)
	view["status"] = label


## Reconciles one view with its entity: position, facing, the form-ring colour, the bar
## fills, and the status label. Cheap per-tick mutation only — no node is created here.
func _update_view(view: Dictionary, entity: SimEntity) -> void:
	var root := view["root"] as Node3D
	var placed := _ground_at(entity.position)
	var moved := placed - root.position
	root.position = placed
	root.visible = not entity.is_dead()  # a downed hero's body vanishes behind the death screen
	if view.has("yaw"):
		HeroModelLibrary.drive_facing(view, view["body"], Vector2(moved.x, moved.z))
	if view.has("ring"):
		var mat := (view["ring"] as MeshInstance3D).material_override as StandardMaterial3D
		var animal := entity.form == AbilitySpec.FORM_ANIMAL
		mat.albedo_color = ANIMAL_RING_COLOR if animal else HUMAN_RING_COLOR
	_set_bar(view["hp_fg"], _fraction(entity.hp, entity.max_hp))
	if view.has("res_node"):
		(view["res_node"] as Node3D).visible = entity.resource_max > 0
		_set_bar(view["res_fg"], _fraction(entity.resource, entity.resource_max))
	if view.has("status"):
		StatusLabel.refresh(view["status"], entity)


## Left-anchors a bar's fill to `frac` of its full width by scaling the foreground quad
## and sliding it so its left edge stays put. The follow-camera holds a fixed yaw, so a
## billboarded quad's local x maps to screen x and the fill always reads horizontally.
func _set_bar(fg: MeshInstance3D, frac: float) -> void:
	fg.scale.x = maxf(frac, 0.0001)
	fg.position.x = -BAR_WIDTH * 0.5 * (1.0 - frac)


## A billboarded HP/resource bar: a dark background quad with a coloured foreground quad
## over it, both returned with the foreground so `_set_bar` can scale the fill.
func _make_bar(fg_color: Color, y: float) -> Dictionary:
	var node := Node3D.new()
	node.position = Vector3(0.0, y, 0.0)
	var bg := MeshInstance3D.new()
	bg.mesh = _bar_quad()
	bg.material_override = _bar_material(HP_BAR_BG)
	node.add_child(bg)
	var fg := MeshInstance3D.new()
	fg.mesh = _bar_quad()
	fg.material_override = _bar_material(fg_color)
	node.add_child(fg)
	return {"node": node, "fg": fg}


func _bar_quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	return quad


func _body_mesh(entity: SimEntity) -> Mesh:
	if entity.is_structure:
		var box := BoxMesh.new()
		var w := NEXUS_SIZE if entity.is_nexus else TOWER_SIZE
		box.size = Vector3(w, STRUCTURE_HEIGHT, w)
		return box
	var capsule := CapsuleMesh.new()
	capsule.radius = CREEP_RADIUS if entity.is_creep else ENTITY_RADIUS
	capsule.height = CREEP_BODY_HEIGHT if entity.is_creep else HERO_BODY_HEIGHT
	return capsule


func _ring_mesh() -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = FORM_RING_RADIUS - FORM_RING_THICKNESS
	torus.outer_radius = FORM_RING_RADIUS
	return torus


## Half the body's height, the lift that stands it on the ground (its origin-centred
## mesh otherwise sinks halfway under y = 0).
func _body_half_height(entity: SimEntity) -> float:
	if entity.is_structure:
		return STRUCTURE_HEIGHT * 0.5
	return (CREEP_BODY_HEIGHT if entity.is_creep else HERO_BODY_HEIGHT) * 0.5


## The height a unit's HP bar floats at — a fixed gap above its own model's measured top, so
## a short body (the chameleon, a slime creep) and a tall one (the hyena, a tower) both read
## with the bar tucked just above them rather than at one shared height tuned to nothing in
## particular. Every field body is now a model, so the one measured-top rule covers heroes,
## creeps, and structures alike; only the pure-CLIENT capsule fallback has no model to measure.
func _hp_bar_y(body: Node3D) -> float:
	return HeroModelLibrary.top_of(body) + HERO_BAR_GAP


func _body_color(entity: SimEntity) -> Color:
	if entity.is_creep:
		return _team_color(entity.team).darkened(CREEP_DARKEN)
	if entity.is_hero:
		return _hero_color(entity)
	return _team_color(entity.team)


func _fraction(current: int, max_value: int) -> float:
	if max_value <= 0:
		return 0.0
	return clampf(float(current) / float(max_value), 0.0, 1.0)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## The jungle short-grass material the ground plane wears: the shared grass shader, which
## breaks the plane into toon-quantised patches of two greens and cel-bands the light to
## match the units. A fresh instance so the one ground plane owns its own material.
func _ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	return mat


## An unshaded, always-camera-facing material with depth-test off, so a floating bar or
## label reads at full colour over the lit world and the foreground quad layers cleanly
## over its background by draw order rather than fighting it on depth.
func _bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	return mat


func _team_color(team: int) -> Color:
	return HERO_COLOR if team == HERO_TEAM else BOT_COLOR


## A hero's draw colour: its team colour shaded by its roster seat, so squadmates on one
## team read apart while still wearing the team hue. A non-hero or a hero whose kit sits in
## no tribe (an unequipped or unknown one) keeps the flat team colour. Structures and creeps
## use `_team_color` directly — only heroes share a team three at a time.
func _hero_color(entity: SimEntity) -> Color:
	var base := _team_color(entity.team)
	var slot := AbilityData.roster_index(entity.kit_id)
	if slot < 0 or slot >= HERO_SHADES.size():
		return base
	var shade := HERO_SHADES[slot]
	return base.lightened(shade) if shade >= 0.0 else base.darkened(-shade)


## This tick's player command — delegated to PlayerInput, handed the world the player acts on,
## their hero, their team, and whether to sample casts. Casts are sampled only with a local
## authoritative sim and while the player is not typing in chat, so a letter in a message never
## fires its QWER bind.
func _sample_player_input() -> InputCommand:
	return _player_input.sample(
		_visible_state(), _player_hero_entity(), _player_team(),
		_sim != null and not _chat_typing(), _pointer_over_minimap()
	)


## Whether the cursor sits over the minimap this tick — the world right-click order is skipped when
## it does, so the panel's own order is the only one (no stray move under the card). False headless.
func _pointer_over_minimap() -> bool:
	return _overlays != null and _overlays.minimap.contains_pointer()


## The state the player acts on: the live sim where this client owns authority (LOCAL/HOST),
## or the latest snapshot on a pure CLIENT. Null before one exists.
func _visible_state() -> SimState:
	if _mode == Mode.CLIENT:
		return _net.latest_state() if _net != null else null
	return _sim.state if _sim != null else null


## The player's team — HERO_TEAM with local authority, the server-assigned team on a CLIENT.
func _player_team() -> int:
	return _my_team if _mode == Mode.CLIENT else HERO_TEAM


## The player's own hero, what movement is measured from: our team's hero in the visible state.
func _player_hero_entity() -> SimEntity:
	var state := _visible_state()
	if state == null:
		return null
	return _local_hero(state) if _mode == Mode.CLIENT else state.get_entity(_hero_id)
