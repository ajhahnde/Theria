extends GutTest
## Round-trip checks on the persisted player settings — today the one update-channel choice.
## They write the real settings file under user://, so each test brackets itself by stashing
## and restoring whatever was there, leaving a developer's own saved channel untouched.

var _saved: String


# Stash and clear the real settings file so each test starts from "nothing saved".
func before_each() -> void:
	if FileAccess.file_exists(Settings.PATH):
		_saved = FileAccess.get_file_as_string(Settings.PATH)
		DirAccess.remove_absolute(Settings.PATH)
	else:
		_saved = ""


# Restore the developer's file, or remove the one a test created.
func after_each() -> void:
	if _saved.is_empty():
		DirAccess.remove_absolute(Settings.PATH)
		return
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_saved)


func test_default_channel_when_nothing_saved() -> void:
	var default := UpdateManifest.CHANNEL_DEFAULT
	assert_eq(Settings.update_channel(), default, "an unset channel reads as the default")


func test_round_trips_the_chosen_channel() -> void:
	Settings.set_update_channel(UpdateManifest.CHANNEL_STABLE)
	var stable := Settings.update_channel()
	assert_eq(stable, UpdateManifest.CHANNEL_STABLE, "Stable persists and reads back")
	Settings.set_update_channel(UpdateManifest.CHANNEL_BETA)
	var beta := Settings.update_channel()
	assert_eq(beta, UpdateManifest.CHANNEL_BETA, "switching back to Beta persists")


func test_a_corrupt_stored_channel_reads_as_the_default() -> void:
	# Simulate a hand-edited file carrying an unknown channel; the read must coerce it to a
	# known id rather than handing the updater an undefined channel.
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.UPDATE_SECTION, Settings.CHANNEL_KEY, "garbage")
	cfg.save(Settings.PATH)
	var read := Settings.update_channel()
	assert_eq(read, UpdateManifest.CHANNEL_BETA, "a corrupt stored id reads as the default")
