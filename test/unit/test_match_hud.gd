extends GutTest
## Behavioural checks on the in-match HUD — the bottom cluster that surfaces the player's
## own hero (name, form, HP/resource, the QWER cooldown bar). They verify it binds to the
## live entity, hides when there is no hero to show, reads the per-form ability bar, and
## reflects the three cast states (ready, on cooldown, blocked on resource). The HUD owns no
## simulation, so this entity-in / readout-out behaviour is the whole of its logic; the
## floating world bars and the camera are the driver's job, not these unit tests.

const LION_HUMAN_Q := 10  # Sunfire Lash — the Lion's human slot-0 ability id


# Builds the HUD in the scene tree so `_ready` lays out its cluster, and frees it at test end.
func _hud() -> MatchHud:
	var hud := MatchHud.new()
	add_child_autoqfree(hud)
	return hud


# A living, kitted hero straight from the sim: equips the kit so the resource pool, the
# per-form ability bar, and the starting form are all set exactly as a real match seats them.
func _hero(kit: String = "lion") -> SimEntity:
	var sim := SimCore.new()
	var id := sim.add_hero(0, Vector2.ZERO, 200.0)
	sim.equip_kit(id, kit)
	return sim.state.get_entity(id)


func test_hides_with_no_hero() -> void:
	var hud := _hud()
	hud.refresh(null)
	assert_false(hud.visible, "the HUD hides when there is no hero to show")


func test_hides_for_a_dead_hero() -> void:
	var hud := _hud()
	var hero := _hero()
	hero.respawn_ticks = 120  # down and counting to respawn — the death screen owns the screen
	hud.refresh(hero)
	assert_false(hud.visible, "the HUD hides while the hero is down")


func test_shows_for_a_living_hero() -> void:
	var hud := _hud()
	hud.refresh(_hero())
	assert_true(hud.visible, "the HUD shows for a living hero")


func test_settings_button_emits_its_signal() -> void:
	var hud := _hud()
	watch_signals(hud)
	hud._settings_button.pressed.emit()
	assert_signal_emitted(hud, "settings_pressed", "the settings button re-emits as settings_pressed")


func test_bottom_cluster_lays_out_on_screen() -> void:
	# Guards the layout regression where the bottom frame, pinned by hand-set anchors on a
	# Container, collapsed to zero size and the whole HUD bar vanished. Container-pinned now,
	# so after a layout pass the frame has a real on-screen size.
	var hud := _hud()
	hud.refresh(_hero())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(hud._frame.size.x, 0.0, "the ability cluster lays out to a real width")
	assert_gt(hud._frame.size.y, 0.0, "the ability cluster lays out to a real height")


func test_binds_name_and_form() -> void:
	var hud := _hud()
	hud.refresh(_hero("lion"))
	assert_eq(hud._name_label.text, "Lion", "the portrait names the hero's kit")
	assert_eq(hud._form_label.text, "HUMAN", "a hero starts in human form")


func test_hp_and_resource_fill_full() -> void:
	var hud := _hud()
	hud.refresh(_hero())
	assert_eq(hud._hp["frac"], 1.0, "a fresh hero is at full HP")
	assert_eq(hud._resource["frac"], 1.0, "a kitted hero starts with a full pool")


func test_resource_fraction_tracks_the_pool() -> void:
	var hud := _hud()
	var hero := _hero()
	hero.resource = hero.resource_max / 2
	hud.refresh(hero)
	assert_almost_eq(hud._resource["frac"], 0.5, 0.02, "the resource bar tracks the pool")


func test_human_slots_show_the_kit_abilities() -> void:
	var hud := _hud()
	hud.refresh(_hero("lion"))
	# Lion human form fills Q (Sunfire Lash), W (Mane Guard), R (Lion Form); E is the
	# animal form's slot and reads empty here.
	assert_eq(hud._cells[0]["name"].text, "Sunfire Lash", "Q carries the human slot-0 ability")
	assert_eq(hud._cells[3]["name"].text, "Lion Form", "R carries the transform")
	assert_eq(hud._cells[2]["name"].text, "", "E is the other form's slot — empty in human form")


func test_ready_ability_wears_the_ready_border() -> void:
	var hud := _hud()
	hud.refresh(_hero("lion"))
	var style: StyleBoxFlat = hud._cells[0]["style"]
	assert_eq(style.border_color, MatchHud.READY_BORDER, "ready when off cooldown and affordable")


func test_cooldown_shows_seconds_and_drains() -> void:
	var hud := _hud()
	var hero := _hero("lion")
	hero.ability_cooldowns[LION_HUMAN_Q] = SimCore.TICK_RATE  # one second of cooldown left
	hud.refresh(hero)
	var cell: Dictionary = hud._cells[0]
	assert_true((cell["wash"] as ColorRect).visible, "the cooldown wash shows while recharging")
	assert_eq((cell["cooldown"] as Label).text, "1", "the readout rounds the cooldown to seconds")
	assert_gt(cell["frac"], 0.0, "the wash fraction tracks the remaining cooldown")


func test_unaffordable_ability_flags_the_resource() -> void:
	var hud := _hud()
	var hero := _hero("lion")
	hero.resource = 0  # off cooldown but the pool is empty
	hud.refresh(hero)
	var style: StyleBoxFlat = hud._cells[0]["style"]
	assert_eq(
		style.border_color,
		MatchHud.NO_RESOURCE_BORDER,
		"an ability blocked only on resource flags the pool, not the timer",
	)
