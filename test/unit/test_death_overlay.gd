extends GutTest
## Behavioural checks on the death screen — the dim + countdown shown while the player's hero
## is down. They verify the countdown shows/hides off the respawn ticks and that the placeholder
## death-recap card is built into the screen, so a regression that drops the recap is caught
## headlessly rather than only in a playtest.


func _overlay() -> DeathOverlay:
	var overlay := DeathOverlay.new()
	add_child_autoqfree(overlay)
	return overlay


# Whether any Label in the subtree carries `text` — the recap card is found by its heading.
func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


func test_hidden_when_alive() -> void:
	var overlay := _overlay()
	overlay.set_respawn(0, 60)
	assert_false(overlay.visible, "the death screen hides while the hero is alive")


func test_shows_countdown_when_down() -> void:
	var overlay := _overlay()
	overlay.set_respawn(120, 60)
	assert_true(overlay.visible, "the death screen shows while the hero is down")
	assert_eq(overlay._timer_label.text, "Respawning in 2", "the countdown rounds ticks to seconds")


func test_recap_card_is_present() -> void:
	var overlay := _overlay()
	assert_true(_has_label(overlay, DeathOverlay.RECAP_TITLE), "the death screen carries the recap")
