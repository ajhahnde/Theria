extends GutTest
## Behavioural checks on the connect menu — the screen shown on a windowed launch
## with no mode flag. They verify each choice maps to the right signal and that a
## blank address falls back to the injected default. The menu owns no networking, so
## this is the whole of its logic; the driver wiring and the live socket are the host
## smoke's job, not these unit tests.


# Builds the menu in the scene tree so `_ready` lays out its controls (the address
# field, the buttons), and frees it when the test ends.
func _menu() -> ConnectMenu:
	var menu := ConnectMenu.new()
	add_child_autoqfree(menu)
	return menu


# Finds the picker item carrying `hero` as metadata and selects it; fails the test if
# no item matches, so a typo'd hero name surfaces rather than silently selecting nothing.
func _select_hero(menu: ConnectMenu, hero: String) -> void:
	for i in menu._hero_picker.item_count:
		if menu._hero_picker.get_item_metadata(i) == hero:
			menu._hero_picker.select(i)
			return
	fail_test("hero %s is not in the picker" % hero)


# Selects the difficulty item carrying `level` as metadata; fails if none matches.
func _select_difficulty(menu: ConnectMenu, level: String) -> void:
	for i in menu._difficulty_picker.item_count:
		if menu._difficulty_picker.get_item_metadata(i) == level:
			menu._difficulty_picker.select(i)
			return
	fail_test("difficulty %s is not in the picker" % level)


func test_practice_choice_requests_a_local_match() -> void:
	var menu := _menu()
	watch_signals(menu)
	menu._on_practice_pressed()
	# With no injected defaults the pickers rest on the first roster hero (the Solane lead)
	# and the first difficulty (Easy).
	assert_signal_emitted_with_parameters(menu, "practice_requested", ["lion", "easy"])


func test_practice_carries_the_picked_hero() -> void:
	var menu := _menu()
	_select_hero(menu, "chameleon")
	watch_signals(menu)
	menu._on_practice_pressed()
	assert_signal_emitted_with_parameters(menu, "practice_requested", ["chameleon", "easy"])


func test_practice_carries_the_picked_difficulty() -> void:
	var menu := _menu()
	_select_difficulty(menu, "hard")
	watch_signals(menu)
	menu._on_practice_pressed()
	assert_signal_emitted_with_parameters(menu, "practice_requested", ["lion", "hard"])


func test_injected_default_preselects_its_difficulty() -> void:
	# default_difficulty must be set before `_ready` populates, so build it outside `_menu()`.
	var menu := ConnectMenu.new()
	menu.default_difficulty = "normal"
	add_child_autoqfree(menu)
	var selected: String = menu._difficulty_picker.get_item_metadata(menu._difficulty_picker.selected)
	assert_eq(selected, "normal", "the driver's default difficulty is pre-selected")


func test_picker_offers_every_tribe_hero() -> void:
	var menu := _menu()
	var total := 0
	for tribe in AbilityData.TRIBE:
		total += (AbilityData.TRIBE[tribe] as Array).size()
	assert_eq(menu._hero_picker.item_count, total, "every hero in every tribe is offered")
	assert_eq(menu._hero_picker.get_item_metadata(0), "lion", "the first item is the Solane lead")


func test_injected_default_preselects_its_hero() -> void:
	# default_hero must be set before `_ready` populates, so build it outside `_menu()`.
	var menu := ConnectMenu.new()
	menu.default_hero = "spider"
	add_child_autoqfree(menu)
	var selected: String = menu._hero_picker.get_item_metadata(menu._hero_picker.selected)
	assert_eq(selected, "spider", "the driver's default hero is pre-selected")


func test_host_choice_requests_a_host() -> void:
	var menu := _menu()
	watch_signals(menu)
	menu._on_host_pressed()
	assert_signal_emitted(menu, "host_requested")


func test_join_carries_the_typed_address() -> void:
	var menu := _menu()
	menu._address_field.text = "10.0.0.7"
	watch_signals(menu)
	menu._on_join_pressed()
	assert_signal_emitted_with_parameters(menu, "join_requested", ["10.0.0.7"])


func test_blank_address_falls_back_to_the_default() -> void:
	var menu := _menu()
	menu.default_address = "203.0.113.9"
	menu._address_field.text = "   "  # whitespace only is treated as blank
	watch_signals(menu)
	menu._on_join_pressed()
	assert_signal_emitted_with_parameters(menu, "join_requested", ["203.0.113.9"])


func test_settings_dialog_preselects_the_saved_channel() -> void:
	# The Settings dialog builds its channel picker on the saved channel, so reopening it
	# always shows the player's current choice rather than resetting to a default.
	var menu := _menu()
	var dialog := menu._build_settings_dialog()
	add_child_autoqfree(dialog)
	var picker: OptionButton = dialog.find_children("", "OptionButton", true, false)[0]
	assert_eq(
		picker.get_item_metadata(picker.selected),
		Settings.update_channel(),
		"the channel picker opens on the saved channel"
	)


func test_settings_dialog_offers_a_manual_update_check() -> void:
	# The Settings dialog carries a force-check button so a player who hears a new build is out can
	# pull it without waiting out the launch-time throttle.
	var menu := _menu()
	var dialog := menu._build_settings_dialog()
	add_child_autoqfree(dialog)
	var labels := PackedStringArray()
	for button in dialog.find_children("", "Button", true, false):
		labels.append((button as Button).text)
	assert_has(labels, "Check for updates now", "the Settings dialog offers a manual update check")
