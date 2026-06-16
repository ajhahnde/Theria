shader_type spatial;
render_mode cull_disabled, specular_disabled;

// The toon treatment every procedural map object wears — the mountain ring, the scattered
// jungle plants, the hills, and the camp props. It is the unit cel shader (src/client/cel.gdshader)
// stripped to the one channel these meshes need: their colour is baked into the mesh as
// per-vertex COLOR by JungleDecor (rock grey rising to a lighter cap, trunk wood, leaf green
// fading to a sun-tipped tip), and the same three-tone light banding folds it into the low-poly
// look so a fern and a hero read as one art family. No texture, no team tint — the colour is
// the geometry's. `cull_disabled` so a thin frond, blade, or banner is lit from both faces and
// never disappears edge-on, which also makes the faceted solids forgiving of winding.

// The two light levels the matte (shadowed) tone steps up through, giving three flat bands in
// all — identical cuts to the unit shader so the toon step matches across the field.
const float MID_TONE = 0.5;
const float LOW_CUT = 0.25;
const float HIGH_CUT = 0.6;

// Canopy fade: when the player's hero stands under tall growth, the parts of it over the hero
// dissolve so the character is never hidden — but the silhouette edge is kept, so a faded tree
// still reads as "a tree you are under" rather than vanishing outright. Driven by main.gd, which
// feeds the hero's world position each frame; the default sits the hero far away so nothing fades
// until a match sets it. The dissolve is a screen-door stipple (discarded fragments on a stable
// per-pixel pattern) — no transparency, so no blend sorting and the toon shading is untouched.
uniform vec3 hero_pos = vec3(1.0e9);
uniform float fade_radius = 680.0;  // horizontal reach of the fade around the hero
uniform float fade_height = 190.0;  // only growth above this (the canopy) fades; trunks/ground stay

varying vec3 v_color;
varying vec3 v_world;

void vertex() {
	v_color = COLOR.rgb;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dxz = distance(v_world.xz, hero_pos.xz);
	float prox = 1.0 - smoothstep(fade_radius * 0.62, fade_radius, dxz);  // 1 over the hero, 0 away
	float tall = smoothstep(fade_height, fade_height + 70.0, v_world.y);  // 0 low, 1 up in the canopy
	// abs() so a flat frond fades whichever way its baked normal points — only a true silhouette
	// edge (normal across the view) is kept opaque, so the hero shows through the canopy over it.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = 1.0 - smoothstep(0.04, 0.30, facing);  // 1 only at the grazing silhouette
	float hide = prox * tall * (1.0 - edge);
	// Stable per-pixel screen-door threshold, so the dissolve stipples instead of blending.
	float dither = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (hide > dither) {
		discard;
	}
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

// Bands the key light into three flat tones with hard edges — the toon step. The shadow side
// is left to the environment's ambient fill (added by the engine), so it reads as a deliberate
// matte tone rather than black, the same as the units standing on top of it.
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float tone = step(LOW_CUT, ndl) * MID_TONE + step(HIGH_CUT, ndl) * (1.0 - MID_TONE);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
