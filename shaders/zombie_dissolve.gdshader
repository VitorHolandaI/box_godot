// SPDX-FileCopyrightText: 2026 Vitor Holanda
// SPDX-License-Identifier: AGPL-3.0-or-later
shader_type spatial;
// Desintegracao estilo "estalo do Thanos": o corpo some em graos de voxel, de
// cima para baixo, com borda de cinza. Nao usar uniforms por instancia: no renderer
// Compatibility o limite e 4096 instancias e 600 zumbis x ~10 pecas estouram
// ("Too many instances using shader instance variables").

uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

const float GRAIN_SIZE = 0.07;
const float EDGE_WIDTH = 0.09;
const vec3 ASH_COLOR = vec3(0.32, 0.29, 0.26);
const vec3 EMBER_COLOR = vec3(0.55, 0.28, 0.12);

varying vec3 grain_position;

float grain_hash(vec3 cell) {
	vec3 p = fract(cell * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Relativo ao no da peca: os graos acompanham o membro enquanto ele anda.
	grain_position = world_position - NODE_POSITION_WORLD;
}

void fragment() {
	float grain = grain_hash(floor(grain_position / GRAIN_SIZE));
	// O topo de cada peca some primeiro; o ruido deixa a borda irregular.
	float top_first = clamp((grain_position.y + 0.6) * 0.25, 0.0, 0.35);
	float survive = grain * 0.72 + (0.35 - top_first);
	if (survive < dissolve_amount) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, EDGE_WIDTH, survive - dissolve_amount);
	edge *= step(0.001, dissolve_amount);
	ALBEDO = mix(albedo_color.rgb, ASH_COLOR, edge);
	EMISSION = EMBER_COLOR * edge * 0.6;
	ROUGHNESS = roughness_value;
}
