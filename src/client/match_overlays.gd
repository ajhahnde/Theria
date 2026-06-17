class_name MatchOverlays
extends CanvasLayer
## The match's screen-space UI layer, lifted out of `main.gd` to keep that file under the line
## cap (the same reason PlayerInput and MoveMarker were lifted). It *is* the canvas layer — a
## direct child of the match scene, exactly like the connect menu and the old death layer, the
## proven way a code-built Control draws in screen space over the zoomed 3D camera. It owns the
## four overlays — the hero HUD, the kill feed, the chat box, and the death screen — and drives
## them from one `update` the driver calls each tick, so main holds one field and one call.
##
## The overlays are added in draw order: HUD, feed, chat, and minimap first; the death dim over
## them; the error screen last of all, so its opaque cover falls over everything when a match fails.
## Built only when there is a display (main skips it on a headless smoke), so every overlay here may
## assume a screen. The error screen owns no networking — main shows it on a failure and acts on its
## two signals (back to menu / quit), the same way the death screen is driven from the hero's state.

var hud: MatchHud
var kill_feed: KillFeed
var chat: MatchChat
var minimap: Minimap
var death: DeathOverlay
var error: ErrorOverlay


func _ready() -> void:
	hud = MatchHud.new()
	hud.settings_pressed.connect(_on_settings_pressed)
	kill_feed = KillFeed.new()
	chat = MatchChat.new()
	minimap = Minimap.new()
	death = DeathOverlay.new()
	error = ErrorOverlay.new()
	# Draw order: the death dim is added over the HUD/minimap; the error cover is added last of all,
	# so a failure's opaque screen layers over the death dim too.
	add_child(hud)
	add_child(kill_feed)
	add_child(chat)
	add_child(minimap)
	add_child(death)
	add_child(error)


## Reconciles every overlay against this tick's world. `focus` is the player's own hero (null
## before it spawns); `team_colors` are the team draw colours indexed by team id, for the kill feed
## and the minimap dots; `tick_rate` converts the respawn ticks the death screen counts down into
## seconds; `hide_fogged` filters the minimap's enemy dots by vision (set only with local authority,
## as a pure CLIENT's snapshot is already team-filtered).
func update(
	focus: SimEntity,
	state: SimState,
	player_team: int,
	team_colors: Array,
	tick_rate: int,
	hide_fogged: bool,
) -> void:
	hud.refresh(focus)
	kill_feed.observe(state, player_team, team_colors)
	minimap.update(state, player_team, focus, team_colors, hide_fogged)
	death.set_respawn(focus.respawn_ticks if focus != null else 0, tick_rate)


## Whether the player is typing in chat — the driver reads this to suppress ability casts so a
## letter in a message never fires its QWER bind.
func is_chat_typing() -> bool:
	return chat.is_typing()


## The settings button placeholder: there is no in-match settings menu yet, so this only notes
## the click. The menu is a later slice; the entry point is wired so adding it is a swap here.
func _on_settings_pressed() -> void:
	print("settings: menu not built yet (placeholder)")
