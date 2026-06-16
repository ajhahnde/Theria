class_name Settings
extends RefCounted
## Player-chosen options that outlive a launch, kept in a single `ConfigFile` at the
## `user://` root — a sibling of the updater's payload sandbox, so a pck swap (which only
## ever writes under `UpdateManifest.PAYLOAD_DIR`) can never wipe them. Today it holds the
## one update-channel choice; video and audio options join it as they land.
##
## Static-only, like `UpdateManifest`: no instance, no node, just typed reads and writes
## over the config file, so callers (the boot scene, the Settings panel) touch settings
## without owning any state. Every read tolerates a missing or corrupt file by returning the
## default — settings are a convenience, never a thing whose absence should stop a launch.

## The settings file, at the user:// root so it survives a payload swap and a reinstall of
## the same client. Created on the first write; absent until the player changes something.
const PATH := "user://settings.cfg"
const UPDATE_SECTION := "update"
const CHANNEL_KEY := "channel"


## The player's saved update channel, normalised to a known id, defaulting to
## `UpdateManifest.CHANNEL_DEFAULT` when nothing is saved yet or the file is unreadable.
## The boot scene reads this to point the updater at the right channel before it checks.
static func update_channel() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return UpdateManifest.CHANNEL_DEFAULT
	var stored: Variant = cfg.get_value(UPDATE_SECTION, CHANNEL_KEY, UpdateManifest.CHANNEL_DEFAULT)
	return UpdateManifest.normalize_channel(str(stored))


## Persists the chosen update channel, normalised so only a known id is ever written.
## Loads first so any other section (future video/audio settings) is preserved across the
## write; a missing file simply starts empty. The change takes effect on the next launch,
## when the boot scene reads it back.
static func set_update_channel(channel: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # ignore the result: a missing file just leaves the config empty
	cfg.set_value(UPDATE_SECTION, CHANNEL_KEY, UpdateManifest.normalize_channel(channel))
	cfg.save(PATH)
