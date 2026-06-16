class_name Updater
extends Node
## The network half of the in-client auto-updater: it reaches the player's chosen release
## channel on GitHub, decides whether a newer `game.pck` is published, downloads it,
## and atomically swaps it into the payload sandbox. The boot scene drives it; all the
## judgements (is-it-newer, is-this-client-new-enough, where-do-files-go) live in the
## network-free `UpdateManifest`, kept apart so they stay unit-testable.
##
## This is the Godot-native form of the-way-out's `updater.py` "author pushes, player
## gets it" loop. There the thin launcher pulled a source zip and swapped an `app/`
## dir; here the client *is* the launcher and the churning part is a `game.pck` the
## boot scene loads over the bundled seed. The semantics are deliberately the same:
## throttled cold-start probe, atomic swap via staged download, a kept-back `.prev`
## for rollback, and fail-soft — any network or integrity failure leaves the working
## install untouched and the client runs whatever it already has.
##
## Hard safety rule (from that updater): every write lands under
## `UpdateManifest.PAYLOAD_DIR`. Player data lives at the `user://` root, a sibling,
## and is never touched — a swap cannot wipe settings or a future save.

## A finished update check. `available` is true only when a newer pck is published
## *and* this client is new enough to load it; `info` carries the build details
## (`sha`, `version`, `pck_url`, `min_client`, `needs_client_upgrade`, `offline`).
signal check_done(available: bool, info: Dictionary)
## Download progress as a 0..1 fraction while a pck is being fetched, for the boot bar.
signal download_progress(ratio: float)
## An apply attempt finished — true when the new pck is live, false when the install
## was left as it was (download, integrity, or swap failure).
signal applied(ok: bool)

## The public GitHub repo, owner and name kept apart (joined only in the API URL) so the
## release path is built from parts rather than a bare "owner/name" slug.
const REPO_OWNER := "ajhahnde"
const REPO_NAME := "Theria"
const MANIFEST_ASSET := "manifest.json"
## GitHub's API wants a User-Agent or it 403s; Accept pins the stable API media type.
const HEADERS: PackedStringArray = [
	"User-Agent: theria-updater",
	"Accept: application/vnd.github+json",
]
## How long a Godot .pck's header magic reads as, used to reject a truncated or
## error-page download before it is ever promoted to the live pck.
const PCK_MAGIC := "GDPC"
## Cold-start probe throttle: after a successful reach, skip the launch-time check
## until this many seconds pass, so a slow link does not stall every launch. The
## in-menu "Check now" path bypasses it.
const CHECK_INTERVAL_S := 86400.0
## Per-request ceiling. A JSON call is tiny; the pck download gets the longer window.
const REQUEST_TIMEOUT_S := 10.0
const DOWNLOAD_TIMEOUT_S := 120.0

## Which release channel the updater pulls, set by the boot scene from the player's saved
## choice before the check runs. Beta (the default) pulls the rolling `playtest` pre-release
## — a fresh pck per push to main; Stable pulls the latest tagged release. Mapped to the
## GitHub releases-API path by `UpdateManifest.release_path`.
var channel := UpdateManifest.CHANNEL_DEFAULT

var _http: HTTPRequest
## True while a pck download is in flight, so `_process` emits progress only then.
var _downloading := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_S
	add_child(_http)


## Emits a download fraction each frame while a pck is being fetched. Body size is
## unknown until the server's headers arrive, so it stays quiet until then.
func _process(_delta: float) -> void:
	if not _downloading:
		return
	var total := _http.get_body_size()
	if total > 0:
		download_progress.emit(clampf(float(_http.get_downloaded_bytes()) / float(total), 0.0, 1.0))


## True when a launch-time probe is worth doing: always on a fresh install (no payload
## yet), otherwise only once `CHECK_INTERVAL_S` has elapsed since the last successful
## reach. Mirrors the-way-out's `should_check` so a captive or slow network does not
## pause every launch by the request timeout.
func should_check() -> bool:
	if not UpdateManifest.has_payload():
		return true
	if not FileAccess.file_exists(UpdateManifest.LAST_CHECK_PATH):
		return true
	var last := FileAccess.get_modified_time(UpdateManifest.LAST_CHECK_PATH)
	return (Time.get_unix_time_from_system() - float(last)) >= CHECK_INTERVAL_S


## Reaches the channel and reports whether an installable update exists, via
## `check_done`. The flow: read the release (for its asset list), read the
## `manifest.json` asset, resolve the pck's download URL from the assets, then judge
## newer-than-installed and client-new-enough. Any unreachable step reports
## `available = false` with `offline = true` so the caller just runs the install it has.
func check() -> void:
	var release := await _get_json(_release_url())
	if not release["ok"]:
		check_done.emit(false, {"offline": true})
		return
	var assets := _asset_urls(release["data"])
	if not assets.has(MANIFEST_ASSET):
		# Reached the channel but it carries no manifest yet (e.g. before the first
		# publish): a clean "nothing to install", not an error.
		_mark_checked()
		check_done.emit(false, {})
		return
	var manifest_resp := await _get_json(assets[MANIFEST_ASSET])
	if not manifest_resp["ok"]:
		check_done.emit(false, {"offline": true})
		return
	_mark_checked()
	var verdict := _judge(manifest_resp["data"], assets)
	check_done.emit(verdict[0], verdict[1])


## Turns a parsed manifest and the release's asset URLs into the `check_done`
## arguments `[available, info]`. An update is offered only when the build is newer
## than the installed sha, its pck asset is actually present, and this client clears
## the pck's `min_client` floor; a newer build this client is too old to load reports
## `available = false` with `needs_client_upgrade = true` so the boot screen can ask
## the player to re-download the client rather than silently doing nothing.
func _judge(manifest_data: Variant, assets: Dictionary) -> Array:
	var m := UpdateManifest.parse(JSON.stringify(manifest_data))
	var info := {
		"sha": m["sha"],
		"version": m["version"],
		"pck_url": assets.get(m["pck"], ""),
		"min_client": m["min_client"],
		"needs_client_upgrade": false,
	}
	var newer := UpdateManifest.is_newer(m["sha"], UpdateManifest.local_sha())
	var has_pck := not (info["pck_url"] as String).is_empty()
	if newer and not UpdateManifest.client_supported(m["min_client"], UpdateManifest.client_version()):
		info["needs_client_upgrade"] = true
		return [false, info]
	return [newer and has_pck, info]


## Downloads the pck named in `info` into the staging slot, verifies it, and swaps it
## live, reporting the outcome via `applied`. On any failure the existing install is
## left exactly as it was — the download lands in `.new` and is only promoted once it
## verifies. Emits `applied(false)` and returns early without touching the live pck.
func apply(info: Dictionary) -> void:
	var url: String = info.get("pck_url", "")
	if url.is_empty():
		applied.emit(false)
		return
	if not _ensure_payload_dir():
		applied.emit(false)
		return
	if not await _download(url, UpdateManifest.PCK_NEW_PATH):
		applied.emit(false)
		return
	if not _is_valid_pck(UpdateManifest.PCK_NEW_PATH):
		DirAccess.remove_absolute(UpdateManifest.PCK_NEW_PATH)
		applied.emit(false)
		return
	applied.emit(_swap_in(info.get("sha", "")))


## Promotes the staged `.new` pck to the live slot: roll the current live pck to
## `.prev` (for rollback), move `.new` into place, and record the installed sha. The
## live pck does not exist only for the instant between the two renames; both are
## within the payload dir (same filesystem) so each is atomic. Returns false on any
## filesystem error, leaving the staged file behind for the next attempt.
func _swap_in(sha: String) -> bool:
	if FileAccess.file_exists(UpdateManifest.PCK_PATH):
		DirAccess.remove_absolute(UpdateManifest.PCK_PREV_PATH)
		if DirAccess.rename_absolute(UpdateManifest.PCK_PATH, UpdateManifest.PCK_PREV_PATH) != OK:
			return false
	if DirAccess.rename_absolute(UpdateManifest.PCK_NEW_PATH, UpdateManifest.PCK_PATH) != OK:
		return false
	var f := FileAccess.open(UpdateManifest.VERSION_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(sha)
	return true


## A GET that returns its body parsed as JSON: `{ok, data}`. `ok` is false on a
## transport error, a non-200 status, or a body that is not valid JSON, so every
## unreachable or malformed response collapses to one "not ok" the callers handle.
func _get_json(url: String) -> Dictionary:
	_http.download_file = ""  # in-memory body, not a file
	if _http.request(url, HEADERS) != OK:
		return {"ok": false}
	var result: Array = await _http.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {"ok": false}
	var json := JSON.new()
	if json.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return {"ok": false}
	return {"ok": true, "data": json.data}


## Downloads `url` straight to `dest`, returning true on a 200. The longer timeout
## covers the pck (a JSON call uses the default); progress is emitted from `_process`
## while `_downloading` holds. Restores the request timeout on the way out.
func _download(url: String, dest: String) -> bool:
	_http.download_file = dest
	_http.timeout = DOWNLOAD_TIMEOUT_S
	_downloading = true
	var ok := false
	if _http.request(url, HEADERS) == OK:
		var result: Array = await _http.request_completed
		ok = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	_downloading = false
	_http.timeout = REQUEST_TIMEOUT_S
	_http.download_file = ""
	return ok


## True when `path` starts with the Godot pack magic, so a truncated download or an
## HTML error page served in place of the pck is rejected before it is swapped live.
func _is_valid_pck(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	return f.get_buffer(4).get_string_from_ascii() == PCK_MAGIC


## Maps each release asset's file name to its download URL, so a manifest's `pck`
## filename and the manifest asset itself resolve to fetchable URLs. Empty when the
## release JSON carries no asset list.
func _asset_urls(release_data: Variant) -> Dictionary:
	var urls := {}
	if typeof(release_data) != TYPE_DICTIONARY:
		return urls
	var assets: Variant = (release_data as Dictionary).get("assets", [])
	if typeof(assets) != TYPE_ARRAY:
		return urls
	for asset in assets:
		if typeof(asset) == TYPE_DICTIONARY and asset.has("name"):
			urls[asset["name"]] = asset.get("browser_download_url", "")
	return urls


func _release_url() -> String:
	var path := UpdateManifest.release_path(channel)
	return "https://api.github.com/repos/%s/%s/%s" % [REPO_OWNER, REPO_NAME, path]


## Creates the payload sandbox if absent. Returns false on a filesystem error, which
## aborts the apply rather than writing outside the dir.
func _ensure_payload_dir() -> bool:
	if DirAccess.dir_exists_absolute(UpdateManifest.PAYLOAD_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(UpdateManifest.PAYLOAD_DIR) == OK


## Records a successful reach to the channel by touching the throttle marker; best
## effort, since a write failure only means the next launch probes again.
func _mark_checked() -> void:
	if not _ensure_payload_dir():
		return
	var f := FileAccess.open(UpdateManifest.LAST_CHECK_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("")
