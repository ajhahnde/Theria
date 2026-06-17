extends GutTest
## Smoke for the fog overlay's build/update path. In the game the overlay is display-gated (skipped
## on a headless run), and its visual tint is only judged in a windowed playtest — so this proves
## the cheap, headless-safe half: the class registers, its shader resource loads, the plane is added
## to the scene, and packing the reveal circles into the shader runs without error.


func test_build_adds_the_fog_plane_and_update_runs() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var fog := FogOverlay.build(root)
	assert_not_null(fog, "the overlay builds")
	assert_eq(root.get_child_count(), 1, "the fog plane is added to the scene")
	# Feed it a couple of reveal circles (a hero and a creep source) — the source-packing path.
	fog.update([
		{"center": Vector2(120.0, -50.0), "radius": Vision.HERO_SIGHT},
		{"center": Vector2(0.0, 0.0), "radius": Vision.CREEP_SIGHT},
	])
	# An empty set is the pre-match case (no sight sources yet) — it must not error.
	fog.update([])
