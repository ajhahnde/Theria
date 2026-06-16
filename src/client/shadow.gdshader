shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// The soft drop shadow a unit casts on the ground — a flat quad laid under each unit, not
// a real shadow-map cast, so it grounds the unit cleanly without the stretched, noisy
// silhouettes a single low light throws across thin low-poly legs. A radial alpha falloff
// fades the dark disc out toward its rim so it reads as a soft blob rather than a coaster.

// The shadow's colour and peak opacity (at the centre), and how much of the radius is the
// soft fade-out edge (0 = a hard disc, 1 = fades the whole way from the centre).
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.32);
uniform float softness : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0; // 0 at centre, 1 at the quad's inscribed edge
	float fade = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * fade;
}
