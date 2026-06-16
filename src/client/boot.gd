extends Control
## The client's entry point: a small update screen that runs before the game. On a plain
## windowed launch it checks the player's chosen update channel, pulls a newer `game.pck` if
## one is published, then loads that payload over the bundled seed and hands off to the match. It
## is the Godot-native form of the-way-out's launcher loop — the client *is* the launcher, so
## "author pushes, player gets it" needs no second app.
##
## It deliberately gets out of the way for every non-player launch. Headless runs, the
## flag-driven modes (`--host`/`--join`/`--local`), and an explicit `--no-update` all skip the
## check and the UI entirely and go straight to the match, so the CI smokes, the GUT suite,
## and a developer launching a mode directly are untouched by the updater. Only a bare
## double-click of the app sees the update screen.
##
## The hand-off is the load-order contract that makes the overriding pck safe: this scene
## touches only the update/launcher classes, so no game class is cached before
## `load_resource_pack` overrides the bundled files; the game's scripts and scenes are loaded
## fresh from the pck the moment `change_scene_to_file` runs.

## The mode flags `main.gd` reads. Their presence means "a specific run was requested" — skip
## the updater and let `main.gd` pick the mode up itself from the same command line.
const MODE_FLAGS: PackedStringArray = ["--host", "--join", "--local"]
const MAIN_SCENE := "res://scenes/main.tscn"
## How long a transient status (up to date, offline, failed) lingers before the hand-off, so
## the player can read it instead of seeing a flash. Kept short — this is a launch, not a wait.
const STATUS_LINGER_S := 0.7

var _status: Label
var _bar: ProgressBar
var _updater: Updater


func _ready() -> void:
	_build_ui()
	if _should_skip():
		_hand_off()
		return
	_updater = Updater.new()
	# Point the updater at the player's saved channel (Stable or Beta) before it probes; an
	# unset or corrupt choice falls back to the default inside Settings.
	_updater.channel = Settings.update_channel()
	add_child(_updater)
	if not _updater.should_check():
		# Within the throttle window: run the installed payload without a network probe, so a
		# slow or captive link does not stall the launch by the request timeout.
		_hand_off()
		return
	_updater.check_done.connect(_on_check_done)
	_updater.download_progress.connect(func(r: float): _bar.value = r)
	_updater.applied.connect(_on_applied)
	_status.text = "Checking for updates…"
	_updater.check()


## True when this launch should bypass the updater: an editor run (the developer path — F5 or
## `godot --path .` — never self-updates), a headless run (no display, the automated smokes), an
## explicit `--no-update`, or any mode flag (a deliberate flag-driven launch that wants the match
## now). Only a plain launch of an exported build reaches the update check.
func _should_skip() -> bool:
	if OS.has_feature("editor"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	var args := OS.get_cmdline_user_args()
	if args.has("--no-update"):
		return true
	for flag in MODE_FLAGS:
		if args.has(flag):
			return true
	return false


## The check finished. Offline or a client too old to load the build runs the installed
## payload; a newer, loadable build is applied (with a progress bar); otherwise we are up to
## date. Each terminal branch records a one-word status for the title-screen footer and hands
## off; the apply branch waits for `applied` instead.
func _on_check_done(available: bool, info: Dictionary) -> void:
	if info.get("offline", false):
		_finish("offline", "Offline — starting installed build")
		return
	if info.get("needs_client_upgrade", false):
		_finish("client update required", "A new Theria is out — please re-download the client")
		return
	if available:
		_status.text = "Updating to %s…" % _label_for(info)
		_bar.visible = true
		_updater.apply(info)
		return
	_finish("up to date", "Up to date")


## An apply attempt finished. On success the freshly swapped pck is live and the footer reads
## "updated"; on failure the install is untouched (the updater left it as it was) and we start
## what we have. Either way the hand-off loads whatever pck is now installed.
func _on_applied(ok: bool) -> void:
	if ok:
		_finish("updated", "Updated — starting Theria")
	else:
		_finish("update failed", "Update failed — starting installed build")


## Records the footer status, shows the message briefly, then hands off — the single exit for
## every terminal branch so the screen always lingers the same beat before the match.
func _finish(status: String, message: String) -> void:
	Engine.set_meta(UiTheme.STATUS_META, status)
	_status.text = message
	_bar.visible = false
	await get_tree().create_timer(STATUS_LINGER_S).timeout
	_hand_off()


## Loads the installed payload over the bundled seed, then changes to the match scene. With no
## payload (a fresh install that has not updated, or an offline first run) the client simply
## runs the seed it shipped with. A failed pack load is non-fatal for the same reason — the
## bundled scene is still there to fall back to.
func _hand_off() -> void:
	if UpdateManifest.has_payload():
		ProjectSettings.load_resource_pack(UpdateManifest.PCK_PATH)
	# Deferred: a skip-path hand-off runs inside `_ready`, when the tree is mid-add and a
	# synchronous scene change is refused; deferring runs it on the next idle frame instead.
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


## A human label for the build being installed: its version when the manifest carried one,
## else a short sha, so the "Updating to …" line always names something.
func _label_for(info: Dictionary) -> String:
	var version: String = info.get("version", "")
	if not version.is_empty():
		return version
	return (info.get("sha", "") as String).substr(0, 7)


## Lays out the update screen: a full-bleed jungle backdrop, the wordmark, a status line, and
## a hidden download bar that only shows while a pck is being fetched. Built in code with the
## shared theme so it reads as the same product as the title screen behind it.
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = UiTheme.BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var wordmark := UiTheme.wordmark()
	if wordmark != null:
		var logo := TextureRect.new()
		logo.texture = wordmark
		logo.custom_minimum_size = Vector2(520, 0)
		logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(logo)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 0)
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.visible = false
	box.add_child(_bar)
