extends GutTest
## Checks on the updater's decision logic — the network-free half. They cover the
## three judgements the live `Updater` leans on: parsing a published manifest without
## trusting it, deciding a remote build is newer, and gating a pck behind the client's
## own version. No HTTP, no display, no file swaps — `Updater` owns those; this is the
## whole of what can be tested deterministically off the wire.


func test_parse_reads_a_well_formed_manifest() -> void:
	var text := '{"version": "0.2.0", "sha": "abc123", "pck": "game.pck", "min_client": "0.1.0"}'
	var m := UpdateManifest.parse(text)
	assert_true(m["ok"], "a valid object parses ok")
	assert_eq(m["sha"], "abc123")
	assert_eq(m["version"], "0.2.0")
	assert_eq(m["pck"], "game.pck")
	assert_eq(m["min_client"], "0.1.0")


func test_parse_rejects_garbage() -> void:
	var m := UpdateManifest.parse("not json at all {{{")
	assert_false(m["ok"], "unparseable text is not ok")
	assert_eq(m["sha"], "", "garbage yields an empty sha, so no update is offered")


func test_parse_rejects_a_non_object() -> void:
	# Valid JSON, but an array — a manifest must be an object to read fields from.
	var m := UpdateManifest.parse('["abc123"]')
	assert_false(m["ok"], "a JSON array is not a manifest")


func test_parse_tolerates_missing_and_mistyped_fields() -> void:
	# sha as a number, no min_client at all — both degrade to empty strings rather
	# than propagating a wrong type into the swap logic.
	var m := UpdateManifest.parse('{"version": "0.2.0", "sha": 5}')
	assert_true(m["ok"], "a partial object still parses")
	assert_eq(m["sha"], "", "a non-string sha reads as empty")
	assert_eq(m["min_client"], "", "an absent field reads as empty")


func test_is_newer_when_shas_differ() -> void:
	assert_true(UpdateManifest.is_newer("def456", "abc123"), "a different remote sha is an update")


func test_is_newer_false_when_shas_match() -> void:
	assert_false(UpdateManifest.is_newer("abc123", "abc123"), "the same sha is not an update")


func test_is_newer_false_when_remote_empty() -> void:
	# Offline or a manifest with no sha: never an update, so the client keeps running
	# whatever is installed.
	assert_false(UpdateManifest.is_newer("", "abc123"), "an empty remote sha is never an update")


func test_is_newer_when_nothing_installed() -> void:
	assert_true(UpdateManifest.is_newer("abc123", ""), "any remote build updates a fresh install")


func test_client_supported_when_floor_met() -> void:
	assert_true(UpdateManifest.client_supported("0.1.0", "0.1.0"), "an equal version meets the floor")
	assert_true(UpdateManifest.client_supported("0.1.0", "0.2.0"), "a newer client clears the floor")


func test_client_supported_false_when_client_too_old() -> void:
	assert_false(
		UpdateManifest.client_supported("0.3.0", "0.1.0"),
		"a pck needing a newer client is refused, asking the player to re-download"
	)


func test_client_supported_with_no_floor() -> void:
	assert_true(UpdateManifest.client_supported("", "0.1.0"), "an empty min_client imposes no floor")


func test_semver_compare_orders_and_pads() -> void:
	assert_eq(UpdateManifest.semver_compare("0.2.0", "0.1.0"), 1, "a > b")
	assert_eq(UpdateManifest.semver_compare("0.1.0", "0.2.0"), -1, "a < b")
	assert_eq(UpdateManifest.semver_compare("0.1", "0.1.0"), 0, "missing parts read as zero")
	assert_eq(UpdateManifest.semver_compare("v1.2.0", "1.2.0"), 0, "a leading v is ignored")


func test_client_version_reads_the_canonical_file() -> void:
	# The build ships res://VERSION ("v0.1.0" today); the leading v is stripped so it
	# compares directly against a manifest min_client.
	assert_false(UpdateManifest.client_version().is_empty(), "the bundled VERSION is readable")
	assert_false(UpdateManifest.client_version().begins_with("v"), "the leading v is stripped")


func test_release_path_maps_each_channel() -> void:
	# Beta names the rolling pre-release by its tag; Stable asks GitHub for the latest
	# non-prerelease release, which the playtest pre-release is invisible to.
	assert_eq(
		UpdateManifest.release_path(UpdateManifest.CHANNEL_BETA),
		"releases/tags/playtest",
		"Beta pulls the rolling playtest pre-release by tag"
	)
	assert_eq(
		UpdateManifest.release_path(UpdateManifest.CHANNEL_STABLE),
		"releases/latest",
		"Stable pulls the latest non-prerelease release"
	)


func test_release_path_falls_back_to_beta_for_an_unknown_channel() -> void:
	# A corrupt or future-written settings value must still resolve to a real channel rather
	# than an undefined API path, so the check never breaks on a bad string.
	assert_eq(
		UpdateManifest.release_path("garbage"),
		"releases/tags/playtest",
		"an unknown channel checks Beta rather than an undefined path"
	)


func test_normalize_channel_coerces_to_a_known_id() -> void:
	assert_eq(UpdateManifest.normalize_channel("stable"), UpdateManifest.CHANNEL_STABLE)
	assert_eq(UpdateManifest.normalize_channel("beta"), UpdateManifest.CHANNEL_BETA)
	assert_eq(
		UpdateManifest.normalize_channel("anything else"),
		UpdateManifest.CHANNEL_BETA,
		"anything but an exact Stable defaults to Beta, never an undefined channel"
	)
