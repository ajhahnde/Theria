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


func test_practice_choice_requests_a_local_match() -> void:
	var menu := _menu()
	watch_signals(menu)
	menu._on_practice_pressed()
	assert_signal_emitted(menu, "practice_requested")


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
