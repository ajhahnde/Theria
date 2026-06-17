extends Node3D
## Presentation + driver for the v0.1 match in three modes (no flag → connect menu; `-- --host` /
## `-- --join [address]` / `-- --local` select directly; headless defaults to LOCAL):
##   LOCAL  — owns the authoritative SimCore; full squad per team, player drives one hero
##            (`--hero`) and bots the rest. The single-machine practice match.
##   HOST   — listen-server: owns the SimCore, drives team 0, hands team 1 to a client on connect
##            (a bot until then), broadcasts a snapshot per tick.
##   CLIENT — no authority: samples input, sends it up, draws snapshots, but predicts its own hero
##            (reconciling each snapshot) and interpolates remote entities a delay in the past.
##            `--netsim <l>,<j>,<loss>` shapes intake.
## Authority in SimCore; transport NetSession; wire NetProtocol; smoothing SnapshotInterpolator.
## Presentation is 2.5D: a flat 2D sim (`Vector2`) under a pitched `Camera3D`, `Vector2(x, y)` →
## `Vector3(x, 0, y)`; each entity owns a pooled 3D view reconciled each tick. Wire untouched.

enum Mode { LOCAL, HOST, CLIENT }

const HERO_SPEED := 215.0
const BOT_SPEED := 200.0
const HERO_TEAM := 0
const BOT_TEAM := 1

const DEFAULT_JOIN_ADDRESS := "127.0.0.1"

## How long a join may sit unanswered before the error screen calls it unreachable. ENet's own
## `connection_failed` does not fire for a dead *localhost* port (UDP, no refusal), so without this
## backstop a join to a down host hangs forever on a static map.
const JOIN_TIMEOUT_MS := 6000

## SceneTree meta set by "Back to Menu" before a reload: it outlives the reload, so the reborn
## client opens the connect menu even when it was launched straight into a mode. Cleared on read.
const FORCE_MENU_META := "theria_force_menu"

## Fixed seed for the `--netsim` conditioner, so a shaped playtest replays the same drops/jitter.
const NETSIM_SEED := 1

# --- Presentation (2.5D) ----------------------------------------------------
# Flat 2D world under a pitched Camera3D, Vector2(x, y) at Vector3(x, 0, y); units 1:1, no rescale.

const HERO_COLOR := Color(0.36, 0.66, 1.0)
const BOT_COLOR := Color(1.0, 0.42, 0.38)

## Hero body: a standing capsule (radius/height). CREEP_* is the smaller wave-member body.
const ENTITY_RADIUS := 44.0
const HERO_BODY_HEIGHT := 150.0
const CREEP_RADIUS := 31.0
const CREEP_BODY_HEIGHT := 80.0
const CREEP_DARKEN := 0.3

## Per-hero tint by roster seat (0..2) so squadmates read apart while the team hue stays. Indexed
## by `AbilityData.roster_index`; +lightens, -darkens; no seat (unknown kit) keeps flat colour.
const HERO_SHADES: Array[float] = [0.0, 0.28, -0.22]

## Structures are boxes: a square footprint (tower/nexus) extruded up by STRUCTURE_HEIGHT.
const TOWER_SIZE := 110.0
const NEXUS_SIZE := 200.0
const STRUCTURE_HEIGHT := 220.0

## Ground + lighting. The plane wears a jungle short-grass shader (GROUND_SHADER — toon-banded
## two greens) over a dark backdrop; key light + ambient fill give the cel-banded units depth.
const GROUND_SHADER: Shader = preload("res://src/client/ground.gdshader")
const BACKDROP_COLOR := Color(0.06, 0.12, 0.09)
const AMBIENT_COLOR := Color(0.52, 0.56, 0.64)
const AMBIENT_ENERGY := 0.5
const LIGHT_ENERGY := 1.1

## Billboarded HP/resource bars + status label above a unit (world units). HP bar floats
## HERO_BAR_GAP above the model's measured top (heights vary); resource bar below, label above.
const BAR_WIDTH := 170.0
const BAR_HEIGHT := 24.0
const HERO_BAR_GAP := 70.0
const RES_BAR_DROP := 36.0
const STATUS_LABEL_RISE := 70.0
const HP_BAR_BG := Color(0.0, 0.0, 0.0, 0.55)
const HP_BAR_FG := Color(0.4, 0.85, 0.4)
const RES_BAR_FG := Color(0.35, 0.6, 0.95)
const STATUS_FONT_SIZE := 120

## LOCAL fallback tribe when `--hero` names no known hero. Rosters in `AbilityData.TRIBE`;
## `_start_local` seats the chosen tribe vs the opposing one. HOST/CLIENT seat the one-per-team
## duel (DUEL_KIT) until the protocol step granting each client a controlled-entity id lands.
const DEFAULT_TRIBE := "solane"

## Kit both heroes mirror in a HOST/CLIENT duel — the one-per-team skeleton until multi-hero wire.
const DUEL_KIT := "lion"

## Form ring under a hero: white while human, amber while shifted to the animal form.
const FORM_RING_RADIUS := 70.0
const FORM_RING_THICKNESS := 12.0
const HUMAN_RING_COLOR := Color(0.95, 0.95, 0.95)
const ANIMAL_RING_COLOR := Color(1.0, 0.62, 0.2)

var _mode: int = Mode.LOCAL
var _join_address := DEFAULT_JOIN_ADDRESS

## True once a mode flag was passed: flagged/headless launches enter directly, bare windowed → menu.
var _explicit_mode := false
## Connect-menu overlay while up; freed once a mode is chosen. Null on flag/headless and post-start.
var _menu_layer: CanvasLayer = null
## False until a mode starts; gates the per-tick driver and draw so the menu sits over a static map.
var _started := false

## CLIENT: simulated link from `--netsim <latency>,<jitter>,<loss>` as `[latency_ms, jitter_ms,
## loss]`, or empty to take snapshots as they arrive. Debug aid for smoothing on a worse link.
var _netsim_params: Array = []

## The authoritative simulation. Present in LOCAL/HOST; null on a pure CLIENT (renders snapshots).
var _sim: SimCore = null
var _bot := BotController.new()
var _hero_id: int = 0
var _bot_id: int = 0

## Samples mouse/keys into an InputCommand; owns move/attack order state. Built once camera exists.
var _player_input: PlayerInput = null
## The on-ground marker drawn at the active move target while the hero walks to it.
var _move_marker: MoveMarker = null

## LOCAL: hero the player drives (`--hero`, any tribe); its tribe fields the player's team, the
## opposing one the bots — picks the match-up. Default tribe's first hero if unknown; net ignores.
var _player_hero: String = AbilityData.TRIBE[DEFAULT_TRIBE][0]
## Bot skill from `--bot-difficulty` or the menu, applied to `_bot` at match start. Defaults to
## "easy" (winnable); "normal"/"hard" sharpen reaction. Held as a name, resolved at apply.
var _bot_difficulty: String = "easy"
## LOCAL: every bot-driven hero (two squadmates + three opponents), each stepped by BotController.
var _bot_ids: Array[int] = []

var _net: NetSession = null
## HOST: the peer id controlling team 1, or 0 while the slot is bot-filled.
var _team1_peer: int = 0
## CLIENT: set once the server has accepted our handshake.
var _joined: bool = false
## CLIENT: tick-time deadline by which the join must complete, else the error screen calls it
## unreachable. Set when the connection starts; ignored once `_joined`.
var _join_deadline_ms: int = 0
## CLIENT: the team the server assigned us; identifies our hero in a snapshot.
var _my_team: int = BOT_TEAM
## CLIENT: world to draw — remote entities interpolated in the past, own hero overlaid at present.
var _client_state: SimState = null
## CLIENT: buffers recent snapshots, interpolating remote entities to smooth jitter and drops.
var _interp := SnapshotInterpolator.new()
## CLIENT: monotonic input seq stamped on each input, so the server's ack matches a pending input.
var _input_seq: int = 0
## CLIENT: unacked inputs (oldest first, `{seq, input}`), replayed onto each snapshot; acks prune.
var _pending_inputs: Array[Dictionary] = []

## Presentation: the follow-camera, ground plane, and per-entity view pool. Each view holds the
## node refs `_update_view` mutates — `{root, body, ring?, hp_node, hp_fg, res_node?, res_fg?,
## status?}` — built once per unit, never rebuilt. Filled in `_build_world`/`_sync_world`.
## The follow-rig (Camera3D, eased target, free-look) is its own class to stay under the line cap.
var _cam: MatchCamera = null
var _ground: MeshInstance3D = null
## Shared map-decor material (JungleDecor); fed the hero's position so growth over it fades.
var _foliage_mat: ShaderMaterial = null
var _views: Dictionary = {}
## Screen-space UI (HUD, kill feed, chat, death screen) built and driven as one layer by
## `MatchOverlays`, reconciled each tick in `_sync_world`. Null on a headless run.
var _overlays: MatchOverlays = null
## Fog-of-war sheet, fed the player team's reveal circles each tick in `_sync_world`. Null headless.
var _fog: FogOverlay = null


func _ready() -> void:
	_build_world()
	_configure_from_cmdline()
	# "Back to Menu" reload lands on the menu; else a flag/headless run enters directly, bare → menu.
	if not _forced_to_menu() and (_explicit_mode or _is_headless()):
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


## Parses `--netsim` `latency,jitter,loss` (ms, ms, 0..1) into `[latency_ms, jitter_ms, loss]`.
## Missing fields default to 0; malformed yields `[]` (conditioner off) with a warning, not a crash.
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


## Records bot skill from `--bot-difficulty` (or the menu), kept only when it names a known level
## so a typo degrades to the current default with a warning, not an unintended difficulty.
func _set_bot_difficulty(level_name: String) -> void:
	if BotController.DIFFICULTY_NAMES.has(level_name):
		_bot_difficulty = level_name
	else:
		push_warning("unknown --bot-difficulty %s; keeping %s (want easy|normal|hard)" % [
			level_name, _bot_difficulty
		])


## Dispatches to the selected mode and marks the match live (starting the per-tick driver and
## draw). Single entry point for both the command-line path and a menu choice.
func _enter_match() -> void:
	_bot.difficulty = BotController.difficulty_from_name(_bot_difficulty)
	var ok := true
	match _mode:
		Mode.HOST:
			ok = _start_host()
		Mode.CLIENT:
			ok = _start_client()
		_:
			_start_local()
	# A failed net start already raised the error screen; leave the driver stopped. LOCAL always runs.
	_started = ok


## A headless run cannot drive a menu (no display/pointer), so it takes a mode from the command
## line (default LOCAL) and never opens the connect screen — keeping smokes flag-driven.
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Whether this start follows a "Back to Menu" reload (SceneTree meta survives it). Cleared on read.
func _forced_to_menu() -> bool:
	if not get_tree().has_meta(FORCE_MENU_META):
		return false
	get_tree().remove_meta(FORCE_MENU_META)
	return true


## Opens the connect menu over a static backdrop; the match begins only once a mode is picked.
## Built in code on its own CanvasLayer so it renders in screen space over the world.
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


## Practice carries the picked hero and bot difficulty, both overriding any `--hero`/
## `--bot-difficulty`. The hero's tribe fields the player's team, the opposing one the bots.
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


## Tears down the connect overlay and enters the chosen match. Shared by every menu choice.
func _close_menu_and_enter() -> void:
	if _menu_layer != null:
		_menu_layer.queue_free()
		_menu_layer = null
	_enter_match()


## Error screen's "Back to Menu": reload the scene and open the menu on the fresh start, so the
## player can pick again without relaunching. A full reload is the simplest correct reset (every
## per-match node/field defaults). The forced-menu flag rides the SceneTree (outlives the reload).
func _return_to_menu() -> void:
	if _net != null:
		_net.close()  # drop the ENet peer before the reload frees its session, so it never lingers
	get_tree().set_meta(FORCE_MENU_META, true)
	get_tree().reload_current_scene()


## The error screen's "Quit".
func _quit_game() -> void:
	get_tree().quit()


## Practice: tribe-vs-tribe. `--hero` names the player's hero; its tribe (`AbilityData.TRIBE`)
## fills the player's team, the opposing tribe the bots, one hero per kit. Player drives the
## matching seat, the other five are bots. Unknown name → default tribe's first hero (no crash).
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


## Seats one hero per kit in `roster` for `team`, fanned across the base fountain and equipped.
## Seat `player_slot` becomes `_hero_id`; others are bot-driven (`_bot_ids`). -1 → all bots.
func _seat_squad(team: int, speed: float, roster: Array[String], player_slot: int) -> void:
	for i in roster.size():
		var id := _sim.add_hero(team, MapData.squad_spawn(team, i, roster.size()), speed)
		_sim.equip_kit(id, roster[i])
		if i == player_slot:
			_hero_id = id
		else:
			_bot_ids.append(id)


## HOST/CLIENT skeleton: one hero per team, both mirroring the duel kit. The wire IDs a hero by
## team, so one-per-team is what the netcode is built around; the LOCAL squad stays off the wire.
func _seat_duel() -> void:
	_sim = _new_world()
	_hero_id = _sim.add_hero(HERO_TEAM, MapData.spawn_for_team(HERO_TEAM), HERO_SPEED)
	_bot_id = _sim.add_hero(BOT_TEAM, MapData.spawn_for_team(BOT_TEAM), BOT_SPEED)
	# Both carry the kit (mirror-fair); the bot drives movement only but shows its form and resource.
	_sim.equip_kit(_hero_id, DUEL_KIT)
	_sim.equip_kit(_bot_id, DUEL_KIT)


## A fresh authoritative world with structures spawned; shared by LOCAL squad and duel seating.
func _new_world() -> SimCore:
	var sim := SimCore.new()
	sim.spawn_structures()
	return sim


func _start_host() -> bool:
	_seat_duel()  # the authoritative world; team 1 is bot-filled until a client takes it
	_net = _make_session()
	var err := _net.start_host()
	if err != OK:
		var detail := "Port %d would not open (error %d) — it may already be in use." % [
			NetSession.DEFAULT_PORT, err
		]
		_fail(ErrorCode.CANT_HOST, detail)
		return false
	_net.client_joined.connect(_on_client_joined)
	_net.client_left.connect(_on_client_left)
	print("hosting on port %d — team 0 is local, team 1 awaits a client" % NetSession.DEFAULT_PORT)
	return true


func _start_client() -> bool:
	_net = _make_session()
	var err := _net.start_client(_join_address)
	if err != OK:
		var detail := "Could not open a connection to %s (error %d)." % [_join_address, err]
		_fail(ErrorCode.CANT_CONNECT, detail)
		return false
	_net.joined_server.connect(_on_joined_server)
	_net.rejected.connect(_on_rejected)
	_net.connect_failed.connect(_on_connect_failed)
	_net.server_left.connect(_on_server_left)
	_join_deadline_ms = Time.get_ticks_msec() + JOIN_TIMEOUT_MS
	if not _netsim_params.is_empty():
		_net.configure_netsim(_netsim_params[0], _netsim_params[1], _netsim_params[2], NETSIM_SEED)
		print(
			"simulating link: %d ms latency, %d ms jitter, %d%% loss"
			% [_netsim_params[0], _netsim_params[1], roundi(_netsim_params[2] * 100.0)]
		)
	print("joining %s:%d" % [_join_address, NetSession.DEFAULT_PORT])
	return true


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
	# Fog of war: the client only receives what its (remote) team sees — authoritative filter, not dim.
	_net.broadcast_snapshot(_sim.state, ack, Vision.visible_ids(_sim.state, NetSession.REMOTE_TEAM))


## Samples input, sends it up with a seq number, buffers it pending, feeds the latest snapshot to
## the interpolator, rebuilds the world. Prediction skips the round-trip; interp smooths the rest.
func _tick_client() -> void:
	if not _joined:
		if Time.get_ticks_msec() > _join_deadline_ms:
			var detail := "No server answered at %s:%d. Check the address, or that a host is running." % [
				_join_address, NetSession.DEFAULT_PORT
			]
			_fail(ErrorCode.UNREACHABLE, detail)
			return
	else:
		_input_seq += 1
		var command := _sample_player_input()
		_net.send_input(_input_seq, command)
		_pending_inputs.append({"seq": _input_seq, "input": command})
	_buffer_snapshots()
	_client_state = _render_state()


## Feeds arrived authoritative snapshots into the interpolation buffer. A `--netsim` conditioner
## releases snapshots once their simulated delay elapsed, stamped with release time so injected
## latency/jitter reads as real arrival; else the freshest as-is. Deduped, so each is buffered once.
func _buffer_snapshots() -> void:
	var now := float(Time.get_ticks_msec())
	if _net.is_conditioned():
		for delivered in _net.drain_snapshots(now):
			_interp.push(delivered["state"], delivered["time"])
	else:
		var state := _net.latest_state()
		if state != null:
			_interp.push(state, now)


## World to draw: remote entities interpolated in the past (smoothing jitter/drops, delay adapts to
## the link), with our own hero overlaid at its predicted present. Both halves derive only from the
## server's snapshots — authority is never forked. Null until the first snapshot.
func _render_state() -> SimState:
	var state := _interp.sample(Time.get_ticks_msec() - _interp.target_delay_ms())
	if state == null:
		return null
	_overlay_predicted_hero(state)
	return state


## Swaps our hero's interpolated `state` position for its predicted present, escaping the delay.
func _overlay_predicted_hero(state: SimState) -> void:
	var predicted := _predicted_hero()
	if predicted == null:
		return
	var hero := _local_hero(state)
	if hero != null:
		hero.position = predicted.position


## Our hero reconciled against the latest snapshot: take its authoritative position, drop inputs the
## server already applied, replay the rest with the server's movement math. The rollback to server
## truth before replay self-corrects a misprediction within a tick. Null before first / if absent.
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
	_fail(ErrorCode.REFUSED, _reason_text(reason))


## Connection timed out, no server answering (host down/wrong address). ENet fires this; else hangs.
func _on_connect_failed() -> void:
	_fail(
		ErrorCode.UNREACHABLE,
		"No server answered at %s:%d. Check the address, or that a host is running." %
		[_join_address, NetSession.DEFAULT_PORT]
	)


func _on_server_left() -> void:
	_fail(ErrorCode.LOST, "The match server is no longer reachable.")


## A handshake refusal reason, turned into a player-facing line. Today the only reason is a
## protocol-version mismatch (the builds differ); an unknown reason still shows, quoting the tag.
func _reason_text(reason: String) -> String:
	if reason == "protocol_version":
		return "The server is running a different version of the game."
	return "The server refused the connection (%s)." % reason


## Halts the match and raises the error screen (code + detail). Headless has no screen, so it exits.
func _fail(code: int, detail: String) -> void:
	push_error("%s [%s]: %s" % [ErrorCode.title(code), ErrorCode.label(code), detail])
	_started = false
	if _overlays != null:
		_overlays.error.show_error(code, detail)
	else:
		get_tree().quit()


# --- Rendering --------------------------------------------------------------


## World to draw: the predicted + interpolated render state on a CLIENT, else the authoritative sim.
func _active_state() -> SimState:
	return _client_state if _mode == Mode.CLIENT else _sim.state


# --- Presentation: 3D world + view pool -------------------------------------
# Sim point Vector2(x, y) sits at Vector3(x, 0, y); each entity owns a pooled view (`_views[id]`).


## A sim point on the 2D field, placed on the 3D ground: Vector2(x, y) -> (x, 0, y).
func _world(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## A sim point on the rolling terrain: the flat point lifted by the hill height under it, so a view
## walks over a mound. Sim stays flat (2D collision/pathing on Y=0); only unit roots ride relief.
func _ground_at(p: Vector2) -> Vector3:
	return _world(p) + Vector3(0.0, JungleDecor.height_at(p), 0.0)


## Builds the static 3D scene once: ground plane, key light + ambient fill for depth, follow-camera
## framing the arena centre. Authored in code (not .tscn) so the editor is never needed.
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
	# Screen-space UI (HUD, kill feed, chat, death screen) over the game camera, like the menu.
	# MatchOverlays owns its canvas layers; built only with a display (skipped headless).
	if not _is_headless():
		_overlays = MatchOverlays.new()
		add_child(_overlays)
		# Minimap emits a clicked world point; one wire orders the hero, one pans the camera.
		_overlays.minimap.order_requested.connect(_on_minimap_order)
		_overlays.minimap.look_requested.connect(_on_minimap_look)
		# The error screen's two exits: tear the failed match down and reopen the menu, or quit.
		_overlays.error.menu_requested.connect(_return_to_menu)
		_overlays.error.quit_requested.connect(_quit_game)
		_fog = FogOverlay.build(self)


## Reconciles the view pool against the live state, then trails the camera. Each tick after the
## step: spawn a view on first sight, update while it persists, free once its id leaves (dead).
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
		# Fog: dim unseen ground, hide enemies. A CLIENT snapshot is pre-filtered; only local auth hides.
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


## Trails the camera on the player's hero — re-pinned each tick it exists, held at its last sighting
## while gone (dead/pre-spawn), unless free-look holds a minimap-panned point that SPACE (ignored
## while typing) drops. MatchCamera eases; this feeds map decor the framed spot so growth fades.
func _follow_camera(state: SimState) -> void:
	var hero := _camera_focus(state)
	var recenter := Input.is_physical_key_pressed(KEY_SPACE) and not _chat_typing()
	_cam.follow(hero.position if hero != null else Vector2.ZERO, hero != null, recenter)
	if _foliage_mat != null:
		_foliage_mat.set_shader_parameter("hero_pos", _world(_cam.target()))


## The camera's unit (the player's hero): LOCAL `_hero_id`, CLIENT its team's hero. Null first.
func _camera_focus(state: SimState) -> SimEntity:
	if _mode == Mode.CLIENT:
		return _local_hero(state)
	if state.entities.has(_hero_id):
		return state.entities[_hero_id]
	return null


## Minimap right-click: issue the move/attack order at that point, via the world right-click path.
func _on_minimap_order(point: Vector2) -> void:
	_player_input.order_at(_visible_state(), _player_hero_entity(), _player_team(), point)


## Minimap left-click/drag: pan the camera there for a free look, held off the hero until re-centre.
func _on_minimap_look(point: Vector2) -> void:
	_cam.look_at_point(point)


## Reconciles the screen-space UI each tick: HUD, kill feed, death screen all read the focus hero
## (camera's hero — sim in LOCAL/HOST, snapshot on CLIENT). Kill feed also takes both team colours.
func _update_overlays(state: SimState) -> void:
	if _overlays == null:
		return
	_overlays.update(
		_camera_focus(state), state, _player_team(), [HERO_COLOR, BOT_COLOR],
		SimCore.TICK_RATE, _mode != Mode.CLIENT,
	)


## Whether the player is typing in chat — casts are suppressed so message letters don't fire QWER.
func _chat_typing() -> bool:
	return _overlays != null and _overlays.is_chat_typing()


## Builds an entity's pooled view: a body, a flat ground ring (heroes), and a billboarded overlay
## (HP bar, plus resource bar + status label for heroes). Returns the refs the update mutates.
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


## Builds an entity's body under `root`: a size-normalised model (hero's animal by kit, tower/nexus,
## or creep slime) via HeroModelLibrary, stood on the ground at on-field size and team-coloured.
## Never mutated after (team/form read tint + ring). A CLIENT hero with no `kit_id` → capsule.
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


## Floating UI above an entity: an HP bar for all, plus resource bar + status label for heroes.
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


## Reconciles one view: position, facing, ring colour, bar fills, status label. No node created.
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


## Left-anchors a bar's fill to `frac` of full width: scale the foreground quad and slide it so the
## left edge stays put. The fixed yaw maps the billboard's local x to screen x (fill horizontal).
func _set_bar(fg: MeshInstance3D, frac: float) -> void:
	fg.scale.x = maxf(frac, 0.0001)
	fg.position.x = -BAR_WIDTH * 0.5 * (1.0 - frac)


## A billboarded bar: a dark bg quad with a coloured fg quad over it; returns both for `_set_bar`.
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


## Half the body height — the lift standing it on the ground (else the centred mesh sinks below 0).
func _body_half_height(entity: SimEntity) -> float:
	if entity.is_structure:
		return STRUCTURE_HEIGHT * 0.5
	return (CREEP_BODY_HEIGHT if entity.is_creep else HERO_BODY_HEIGHT) * 0.5


## HP bar height: a fixed gap above the model's measured top, so a short body (chameleon, slime) and
## a tall one (hyena, tower) both tuck the bar just above. Every field body is a model, so one
## measured-top rule covers heroes/creeps/structures; only the CLIENT capsule fallback has none.
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


## The ground plane's jungle short-grass material: the shared grass shader (toon-quantised patches
## of two greens, cel-banded light to match units). A fresh instance so the plane owns its material.
func _ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	return mat


## An unshaded, billboarded material with depth-test off, so a floating bar/label reads at full
## colour over the lit world and the fg quad layers over its bg by draw order, not depth.
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


## A hero's draw colour: team colour shaded by roster seat, so squadmates read apart while keeping
## the team hue. A hero whose kit sits in no tribe keeps the flat colour (only heroes share a team).
func _hero_color(entity: SimEntity) -> Color:
	var base := _team_color(entity.team)
	var slot := AbilityData.roster_index(entity.kit_id)
	if slot < 0 or slot >= HERO_SHADES.size():
		return base
	var shade := HERO_SHADES[slot]
	return base.lightened(shade) if shade >= 0.0 else base.darkened(-shade)


## This tick's player command via PlayerInput, handed the world, hero, team, and whether to sample
## casts. Casts only with a local sim and not typing, so a message letter never fires its QWER bind.
func _sample_player_input() -> InputCommand:
	return _player_input.sample(
		_visible_state(), _player_hero_entity(), _player_team(),
		_sim != null and not _chat_typing(), _pointer_over_minimap()
	)


## Cursor over the minimap: world right-click order is skipped (panel's own only). False headless.
func _pointer_over_minimap() -> bool:
	return _overlays != null and _overlays.minimap.contains_pointer()


## State the player acts on: the live sim with local authority (LOCAL/HOST), else latest snapshot.
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
