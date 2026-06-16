class_name MatchOverlays
extends CanvasLayer
## The match's screen-space UI layer, lifted out of `main.gd` to keep that file under the line
## cap (the same reason PlayerInput and MoveMarker were lifted). It *is* the canvas layer — a
## direct child of the match scene, exactly like the connect menu and the old death layer, the
## proven way a code-built Control draws in screen space over the zoomed 3D camera. It owns the
## four overlays — the hero HUD, the kill feed, the chat box, and the death screen — and drives
## them from one `update` the driver calls each tick, so main holds one field and one call.
##
## The four are added in draw order: HUD, feed, and chat first, the death screen last, so the
## death dim falls over the rest when the player's hero is down. Built only when there is a
## display (main skips it on a headless smoke), so every overlay here may assume a screen.

var hud: MatchHud
var kill_feed: KillFeed
var chat: MatchChat
var death: DeathOverlay


func _ready() -> void:
	hud = MatchHud.new()
	hud.settings_pressed.connect(_on_settings_pressed)
	kill_feed = KillFeed.new()
	chat = MatchChat.new()
	death = DeathOverlay.new()
	# Draw order: the death screen is added last so its dim layers over the HUD when shown.
	add_child(hud)
	add_child(kill_feed)
	add_child(chat)
	add_child(death)


## Reconciles every overlay against this tick's world. `focus` is the player's own hero (null
## before it spawns); `team_colors` are the team draw colours indexed by team id, for the kill
## feed; `tick_rate` converts the respawn ticks the death screen counts down into seconds.
func update(
	focus: SimEntity, state: SimState, player_team: int, team_colors: Array, tick_rate: int
) -> void:
	hud.refresh(focus)
	kill_feed.observe(state, player_team, team_colors)
	death.set_respawn(focus.respawn_ticks if focus != null else 0, tick_rate)


## Whether the player is typing in chat — the driver reads this to suppress ability casts so a
## letter in a message never fires its QWER bind.
func is_chat_typing() -> bool:
	return chat.is_typing()


## The settings button placeholder: there is no in-match settings menu yet, so this only notes
## the click. The menu is a later slice; the entry point is wired so adding it is a swap here.
func _on_settings_pressed() -> void:
	print("settings: menu not built yet (placeholder)")
