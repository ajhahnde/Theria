shader_type spatial;
render_mode specular_disabled;

// The cel / toon treatment every field unit wears (heroes, creeps, structures). It
// reproduces a model's own surface albedo — the imported texture, its base colour, and
// its vertex colours where the source used them — so a stylised model still reads as
// itself, then quantises the directional light into three flat tones for the low-poly
// look and folds in the unit's team colour. Driven per surface by HeroModelLibrary,
// which copies the source material's albedo into these uniforms.

// The source surface's albedo: a texture (white when the model carries none), a base
// colour multiplied over it, and a flag for whether the source fed vertex colours into
// its albedo (the low-poly animals do; the textured structures do not).
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float use_vertex = 0.0;

// The team wash: the colour the albedo is mixed toward, and how far (0 keeps the model's
// own colour, 1 replaces it). A hero takes a light mix to keep its species; a prop more.
uniform vec4 team_tint : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

// A hard-edged fresnel rim that lights the model's silhouette, so a unit pops off the
// jungle ground it stands on instead of blending into it. `rim_sharpness` is where the
// rim starts toward the edge (higher = thinner band); `rim_amount` how bright it burns.
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_sharpness : hint_range(0.0, 1.0) = 0.45;
uniform float rim_amount : hint_range(0.0, 2.0) = 0.8;

// The two light levels the matte (shadowed) tone steps up through, giving three flat
// bands in all. Eyeball-calibrated against the single key light and the ambient fill.
const float MID_TONE = 0.5;
const float LOW_CUT = 0.25;
const float HIGH_CUT = 0.6;

varying vec3 v_color;

void vertex() {
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_tex, UV).rgb;
	base = mix(base, base * v_color, use_vertex);
	ALBEDO = mix(base, team_tint.rgb, tint_strength);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_sharpness, 1.0, fresnel);
	EMISSION += rim_color.rgb * rim * rim_amount;
}

// Bands the key light into three flat tones with hard edges — the toon step. The
// shadow side is left to the environment's ambient fill (added by the engine), so it
// reads as a deliberate matte tone rather than going black.
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float tone = step(LOW_CUT, ndl) * MID_TONE + step(HIGH_CUT, ndl) * (1.0 - MID_TONE);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tone;
}
