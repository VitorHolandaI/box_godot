shader_type spatial;

uniform vec3 dirt_base : source_color = vec3(0.42, 0.31, 0.20);
uniform vec3 dirt_dark : source_color = vec3(0.22, 0.15, 0.10);
uniform vec3 grass_hint : source_color = vec3(0.27, 0.34, 0.14);
uniform float scale_large : hint_range(0.001, 0.2) = 0.02;
uniform float scale_small : hint_range(0.001, 0.5) = 0.12;
uniform float patch_scale : hint_range(0.0005, 0.05) = 0.006;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	float n_large = value_noise(uv * scale_large);
	float n_small = value_noise(uv * scale_small + vec2(13.0, 7.0));
	vec3 dirt = mix(dirt_dark, dirt_base, n_large);
	dirt = mix(dirt, dirt_base + vec3(0.05, 0.035, 0.02), n_small);
	float patch = value_noise(uv * patch_scale + vec2(3.1, 9.2));
	vec3 color = mix(dirt, grass_hint, smoothstep(0.5, 0.72, patch) * 0.4);
	ALBEDO = color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
