class_name NetSession
extends Node
## The transport layer for the listen-server: it owns the ENet peer and the RPCs
## that carry input up to the authoritative server and snapshots back down.
##
## This is the only place the engine's networking is touched. All wire shaping
## lives in NetProtocol (pure, tested); all authority lives in SimCore (pure,
## tested). NetSession just moves bytes and tracks who is connected, so the
## untestable socket surface stays as thin as possible.
##
## Topology: one peer hosts (a listen-server) and is the multiplayer
## authority — peer id 1 — running the only real SimCore. A remote client renders
## the snapshots it receives and sends its input up; it never simulates. On
## connect the two exchange PROTOCOL_VERSION and a mismatch is refused, so an
## incompatible client can never feed or desync the authoritative world.

## Server: a verified client finished the handshake and now controls `team`.
signal client_joined(peer_id: int, team: int)
## Server: a client dropped; its slot reverts to a bot.
signal client_left(peer_id: int)
## Client: the server accepted us; we control `team`.
signal joined_server(team: int)
## Client: the server refused us (today: a protocol-version mismatch).
signal rejected(reason: String)
## Client: the server connection was lost.
signal server_left

## The walking skeleton seats one remote player (team 1); the host is team 0.
const DEFAULT_PORT := 8642
const MAX_CLIENTS := 1
const REMOTE_TEAM := 1

var is_server: bool = false

## Server: latest input per connected peer id. Held until superseded — an
## unreliable packet may be dropped, so the last known intent persists rather
## than snapping the unit to a halt on a single lost frame.
var _latest_inputs: Dictionary = {}

## Server: the sequence number of each peer's latest input. Echoed back in the
## snapshot as the peer's `ack` so the client can prune the inputs the server has
## already applied and replay only the rest.
var _latest_input_seqs: Dictionary = {}

## Client: the most recent snapshot Dictionary, or empty until the first arrives.
var _latest_snapshot: Dictionary = {}


## Starts hosting on `port`. Returns OK or an ENet error; on success this peer is
## the multiplayer authority and runs the authoritative simulation.
func start_host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	return OK


## Connects to a host at `address`:`port`. Returns OK or an ENet error. The
## protocol handshake runs once the transport connects.
func start_client(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(func() -> void: server_left.emit())
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_latest_inputs.clear()
	_latest_input_seqs.clear()
	_latest_snapshot = {}


# --- Server side ------------------------------------------------------------


## Broadcasts the authoritative world to every client. Called once per tick by the
## host driver, after the simulation has stepped. `ack` is the sequence number of
## the remote input applied this tick, so the client can reconcile against it.
func broadcast_snapshot(state: SimState, ack: int = -1) -> void:
	_push_snapshot.rpc(NetProtocol.encode_snapshot(state, ack))


## The last input received from `peer_id`, or null if none has arrived yet.
func input_for(peer_id: int) -> InputCommand:
	return _latest_inputs.get(peer_id, null)


## The sequence number of `peer_id`'s last input, or -1 if none has arrived. The
## host passes this to `broadcast_snapshot` as the tick's ack.
func input_seq_for(peer_id: int) -> int:
	return _latest_input_seqs.get(peer_id, -1)


func _on_server_peer_disconnected(peer_id: int) -> void:
	_latest_inputs.erase(peer_id)
	_latest_input_seqs.erase(peer_id)
	client_left.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _submit_hello(protocol_version: int) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if protocol_version != NetProtocol.PROTOCOL_VERSION:
		_reject.rpc_id(peer_id, "protocol_version")
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	_accept.rpc_id(peer_id, REMOTE_TEAM)
	client_joined.emit(peer_id, REMOTE_TEAM)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _push_input(data: Array) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	_latest_inputs[peer_id] = NetProtocol.decode_input(data)
	_latest_input_seqs[peer_id] = NetProtocol.decode_input_seq(data)


# --- Client side ------------------------------------------------------------


## Sends this tick's intent up to the server, stamped with `seq` so the server can
## acknowledge it. A no-op before the handshake.
func send_input(seq: int, command: InputCommand) -> void:
	_push_input.rpc_id(1, NetProtocol.encode_input(seq, command))


func has_snapshot() -> bool:
	return not _latest_snapshot.is_empty()


## Decodes and returns the latest authoritative world, or null if none yet.
func latest_state() -> SimState:
	if _latest_snapshot.is_empty():
		return null
	return NetProtocol.decode_snapshot(_latest_snapshot)


## The sequence number of the last input the server had applied in the latest
## snapshot, or -1 if none. The client prunes inputs at or below this and replays
## the rest onto the snapshot to predict its hero.
func latest_ack() -> int:
	return _latest_snapshot.get("ack", -1)


func _on_connected_to_server() -> void:
	_submit_hello.rpc_id(1, NetProtocol.PROTOCOL_VERSION)


@rpc("authority", "call_remote", "reliable")
func _accept(team: int) -> void:
	joined_server.emit(team)


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	rejected.emit(reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func _push_snapshot(data: Dictionary) -> void:
	_latest_snapshot = data
