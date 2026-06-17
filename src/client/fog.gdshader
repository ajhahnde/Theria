shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The fog of war: a dark sheet laid just over the playfield that dims everywhere the player's
// team has no vision, with a clear hole punched around each of the team's sight sources (its
// heroes, creeps, and structures). It is a presentation tint only — enemy units in fog are
// hidden by the renderer and never sent over the wire (Vision / NetProtocol), so this draws no
// units, only the darkened ground. World-space and unshaded so the tint reads flat and even
// across the arena regardless of where the plane sits; depth-tested (it does not write depth) so
// the 3D bodies standing in a lit circle rise in front of it rather than being dimmed.

// The reveal circles, packed (center.x, center.z, radius, _) in world units — one per sight
// source the driver feeds each frame, up to MAX_SOURCES. Only the first `source_count` are read,
// so the unused tail never reveals.
const int MAX_SOURCES = 64;
uniform vec4 fog_sources[MAX_SOURCES];
uniform int source_count = 0;

// The fog tint and how opaque it sits over unseen ground, plus the soft inner band: the sheet
// fades from clear at a circle's edge to full fog `fog_edge` units outside it, so the reveal has
// a feathered rim rather than a hard ring.
uniform vec3 fog_color : source_color = vec3(0.02, 0.03, 0.06);
uniform float fog_alpha : hint_range(0.0, 1.0) = 0.82;
uniform float fog_edge = 220.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The signed distance to the nearest reveal edge: negative inside a circle, positive in fog.
	float nearest = 1.0e9;
	for (int i = 0; i < source_count; i++) {
		nearest = min(nearest, distance(world_pos.xz, fog_sources[i].xy) - fog_sources[i].z);
	}
	// No sources yet (pre-match, before a hero spawns) means no vision data — leave the field
	// clear rather than blacking it out, so the menu backdrop and the first frame read normally.
	float alpha = source_count == 0 ? 0.0 : fog_alpha * smoothstep(0.0, fog_edge, nearest);
	ALBEDO = fog_color;
	ALPHA = alpha;
}
