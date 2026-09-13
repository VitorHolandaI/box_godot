shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec3 rust_tint : source_color = vec3(0.46, 0.24, 0.14);
uniform vec3 rust_dark : source_color = vec3(0.22, 0.13, 0.08);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.7;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.5;
uniform bool is_burnt = false;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV);

	if (is_burnt) {
		float soot = noise2d(world_pos.xz * 3.0);
		vec3 charred = mix(vec3(0.12, 0.12, 0.12), vec3(0.04, 0.04, 0.04), soot);
		ALBEDO = mix(base.rgb * 0.15, charred, 0.85);
		ROUGHNESS = 0.98;
		METALLIC = 0.02;
	} else {
		float n_coarse = noise2d(world_pos.xz * 1.5 + world_pos.y * 2.0);
		float n_fine = noise2d(world_pos.xz * 6.0 + world_pos.y * 4.0);
		float rust_mask = smoothstep(1.0 - rust_amount, 1.25 - rust_amount * 0.5, (n_coarse * 0.65 + n_fine * 0.35));

		vec3 rust = mix(rust_tint, rust_dark, n_fine);
		vec3 faded_base = mix(base.rgb, vec3(dot(base.rgb, vec3(0.3, 0.59, 0.11))), 0.35);
		faded_base = mix(faded_base, vec3(0.18, 0.16, 0.14), dirt_amount * 0.4);

		ALBEDO = mix(faded_base, rust, rust_mask);
		ROUGHNESS = mix(0.65, 0.96, rust_mask);
		METALLIC = mix(0.25, 0.04, rust_mask);
	}
}
