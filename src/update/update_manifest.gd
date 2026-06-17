class_name UpdateManifest
extends RefCounted
## The pure, network-free half of the auto-updater: parsing the published
## `manifest.json`, deciding whether the remote build is newer than the installed
## one, gating an install behind the client's own version, and naming every path
## the updater touches. Split out from `Updater` so all the decision logic stays
## unit-testable with no HTTP, no display, and no scene tree — `Updater` owns the
## `HTTPRequest` and the file swaps and leans on this for the judgements.
##
## A published build is identified by its git commit `sha` (the rolling `main`
## channel re-publishes a fresh `game.pck` per green push). The installed sha is
## written to `.version` after a successful swap, so "is there an update" is a plain
## string compare — exactly the model the-way-out's updater uses, adapted from a
## branch tip to a per-build sha.
##
## Hard safety rule mirrored from that updater: every path here lives under
## `PAYLOAD_DIR` (`user://payload/`). Player data (settings, future saves) lives at
## the `user://` root, a *sibling* of the payload dir, so a pck swap can never reach
## it. Nothing in the updater ever writes outside `PAYLOAD_DIR`.

## The sandbox the updater owns. The live pck, the staged download, the kept-back
## previous pck, and the installed-sha marker all live here; player data never does.
const PAYLOAD_DIR := "user://payload"
## The live game payload the boot scene loads over the bundled seed.
const PCK_PATH := PAYLOAD_DIR + "/game.pck"
## Where a download lands before it is promoted to the live pck — so a failed or
## partial download never replaces a working install.
const PCK_NEW_PATH := PAYLOAD_DIR + "/game.pck.new"
## The previous live pck, kept after a successful swap for manual rollback.
const PCK_PREV_PATH := PAYLOAD_DIR + "/game.pck.prev"
## The git sha of the installed pck, written after a swap; empty/absent before the
## first successful update (the client then runs its bundled seed).
const VERSION_PATH := PAYLOAD_DIR + "/.version"
## The human version string of the installed pck (the manifest's `version`), written
## alongside the sha after a swap. Read by the menu footer so it names the *content* the
## player is running rather than the launcher's frozen `config/version`. Empty/absent
## before the first update or after a swap that predates this marker (an older install
## carries only `.version`); the footer then falls back to the launcher version.
const PAYLOAD_VERSION_PATH := PAYLOAD_DIR + "/.payload_version"
## Touched after every successful reach to the channel; its mtime throttles the
## cold-start probe (see `Updater.should_check`).
const LAST_CHECK_PATH := PAYLOAD_DIR + "/.last_check"
## The project setting holding the client's own version — the in-engine mirror of the
## canonical VERSION file (kept in lockstep by the drift gate), read to gate a pck whose
## `min_client` outruns this binary. Read from ProjectSettings rather than the loose
## `res://VERSION`: the bare VERSION file is not a resource, so `export_filter` drops it from
## an exported launcher, where `config/version` is always present — so the export reads its
## own version correctly instead of reading empty and refusing every update.
const CLIENT_VERSION_SETTING := "application/config/version"

## The two update channels the player can pick between (persisted by `Settings`). Beta
## pulls the rolling `playtest` pre-release — a fresh pck per green push to main; Stable
## pulls the latest tagged, non-prerelease GitHub Release, so it moves only on a cut
## release. Beta is the default: it is the channel the updater shipped on, and the one
## with a payload before the first Stable target is tagged.
const CHANNEL_BETA := "beta"
const CHANNEL_STABLE := "stable"
const CHANNEL_DEFAULT := CHANNEL_BETA
## The rolling pre-release tag the Beta channel pulls (the only channel before v0.2.0).
const BETA_TAG := "playtest"


## Parses the published manifest JSON into a typed dictionary, tolerating anything
## malformed: a parse failure or a non-object yields `ok = false` and empty fields,
## so a corrupt or truncated manifest degrades to "no update" rather than a crash.
## Returns `{ok, version, sha, pck, min_client}` with string fields defaulted empty.
static func parse(json_text: String) -> Dictionary:
	var blank := {"ok": false, "version": "", "sha": "", "pck": "", "min_client": ""}
	# JSON.new().parse() returns the error code without pushing an engine error, unlike
	# the static JSON.parse_string() — so a malformed manifest stays a quiet "no update".
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return blank
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return blank
	return {
		"ok": true,
		"version": _string_field(data, "version"),
		"sha": _string_field(data, "sha"),
		"pck": _string_field(data, "pck"),
		"min_client": _string_field(data, "min_client"),
	}


## Reads `key` from a parsed manifest as a trimmed string, defaulting empty when the
## key is missing or not a string — so a number or null in the JSON never propagates.
static func _string_field(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key, "")
	if typeof(value) != TYPE_STRING:
		return ""
	return (value as String).strip_edges()


## True when `remote_sha` names a build we should install: it is non-empty and
## differs from `local_sha`. An empty remote (manifest missing the sha, or offline)
## is never an update; an empty local (nothing installed yet) makes any remote one.
static func is_newer(remote_sha: String, local_sha: String) -> bool:
	if remote_sha.is_empty():
		return false
	return remote_sha != local_sha


## True when this client is new enough to run a pck declaring `min_client`. An empty
## or unparseable `min_client` imposes no floor (true). The gate is the escape hatch
## for a pck built against a changed engine/autoload set: bump `min_client` and old
## launchers refuse the load and ask the player to re-download instead of crashing.
static func client_supported(min_client: String, client_version: String) -> bool:
	if min_client.strip_edges().is_empty():
		return true
	return semver_compare(client_version, min_client) >= 0


## Compares two dotted version strings numerically, ignoring a leading `v` and any
## non-numeric suffix on a part. Returns -1 / 0 / +1 for a < b / a == b / a > b.
## Missing trailing parts read as zero, so "0.1" == "0.1.0".
static func semver_compare(a: String, b: String) -> int:
	var pa := _version_parts(a)
	var pb := _version_parts(b)
	var n: int = maxi(pa.size(), pb.size())
	for i in n:
		var ai: int = pa[i] if i < pa.size() else 0
		var bi: int = pb[i] if i < pb.size() else 0
		if ai != bi:
			return -1 if ai < bi else 1
	return 0


## Splits a version string into integer parts, dropping a leading `v` and reading the
## leading digits of each dotted segment (so "1.2.0-rc1" -> [1, 2, 0]).
static func _version_parts(version: String) -> Array[int]:
	var trimmed := version.strip_edges().lstrip("v")
	var parts: Array[int] = []
	for segment in trimmed.split("."):
		parts.append(_leading_int(segment))
	return parts


## The integer value of the leading digit run of `segment`, or 0 if it starts with no
## digit — so a tagged or suffixed segment compares on its numeric head alone.
static func _leading_int(segment: String) -> int:
	var digits := ""
	for c in segment:
		if c < "0" or c > "9":
			break
		digits += c
	return digits.to_int() if not digits.is_empty() else 0


## The git sha of the installed pck, read from `.version`, or empty when nothing has
## been installed yet (the client is running its bundled seed). Best-effort: any read
## failure reads as "nothing installed", which simply makes the next check offer an update.
static func local_sha() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return ""
	var f := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()


## The human version string of the installed pck (the manifest's `version`), read from
## `.payload_version`, or empty when nothing has been installed yet or the install predates
## this marker. Best-effort, like `local_sha`: any read failure reads as "unknown", which
## the footer treats as a cue to show the launcher's own version instead.
static func payload_version() -> String:
	if not FileAccess.file_exists(PAYLOAD_VERSION_PATH):
		return ""
	var f := FileAccess.open(PAYLOAD_VERSION_PATH, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()


## This client's own version, read from the `config/version` project setting baked into the
## build, with a leading `v` stripped so it compares directly against a manifest's
## `min_client`. Always present in the editor and in any export (it is a core project
## setting); empty only if somehow unset, which reads as the lowest version.
static func client_version() -> String:
	return str(ProjectSettings.get_setting(CLIENT_VERSION_SETTING, "")).strip_edges().lstrip("v")


## True when a runnable game payload is installed — the boot scene loads it over the
## bundled seed; absent, the client runs the seed it shipped with.
static func has_payload() -> bool:
	return FileAccess.file_exists(PCK_PATH)


## Whether the boot scene should load the installed payload pck over the bundled files. Only an
## exported player build may: an editor/source run (`is_editor`) must play its own `res://`
## source even when a payload is present, or the last-downloaded shipped pck silently shadows
## uncommitted changes — the trap that made a freshly-built HUD look like it would not render.
## Pure (takes the two facts as arguments) so the rule is unit-testable without a real pck or
## the editor feature flag.
static func should_load_payload(is_editor: bool, payload_present: bool) -> bool:
	return payload_present and not is_editor


## The GitHub releases-API path segment a channel resolves to, appended to
## `repos/<owner>/<name>/`. Beta names the rolling pre-release by its tag; Stable asks for
## `releases/latest`, which GitHub defines as the newest non-prerelease, non-draft release
## — so the `playtest` pre-release is invisible to Stable and only a cut tag moves it. An
## unrecognised channel falls back to Beta's path, so a corrupt setting still checks.
static func release_path(channel: String) -> String:
	if channel == CHANNEL_STABLE:
		return "releases/latest"
	return "releases/tags/" + BETA_TAG


## Coerces any stored or passed channel string to a known channel id, defaulting to Beta
## for anything but an exact Stable — so a hand-edited or future-written settings value can
## never put the updater in an undefined channel.
static func normalize_channel(channel: String) -> String:
	return CHANNEL_STABLE if channel == CHANNEL_STABLE else CHANNEL_BETA
