shader_type spatial;

// Asfalto da rua: sem textura de arquivo, tudo procedural em espaco de mundo.
// A rua e a maior area continua da tela e como chapa cinza lisa ela achatava a
// cidade inteira. Aqui ela ganha grao, remendos de manutencao, trinca e a
// faixa central amarela desbotada.
//
// Uso: material de `assemble_roads` em city_assembler.gd. O `lane_half_width`
// e metade da largura da rua, para a faixa cair no meio e a sarjeta na borda.

uniform vec3 asphalt_color : source_color = vec3(0.075, 0.080, 0.085);
uniform vec3 patch_color : source_color = vec3(0.115, 0.115, 0.118);
uniform vec3 lane_color : source_color = vec3(0.72, 0.60, 0.16);
uniform float lane_half_width : hint_range(0.5, 12.0) = 3.0;
// Faixa central: comprimento do traco e do vao, em metros.
uniform float dash_length : hint_range(0.5, 8.0) = 2.4;
uniform float dash_gap : hint_range(0.5, 8.0) = 2.6;
uniform float detail_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;
varying vec2 local_pos;

float road_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float road_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(road_hash(i), road_hash(i + vec2(1.0, 0.0)), u.x),
		mix(road_hash(i + vec2(0.0, 1.0)), road_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float road_fbm(vec2 p) {
	return road_noise(p) * 0.6 + road_noise(p * 2.3 + vec2(5.2, 1.3)) * 0.3 + road_noise(p * 5.1) * 0.1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Coordenada da propria rua: x atravessa a pista, y corre ao longo dela.
	local_pos = VERTEX.xz;
}

void fragment() {
	vec3 albedo = asphalt_color;
	float roughness = 0.92;
	if (detail_strength > 0.001) {
		vec2 uv = world_pos.xz;
		float grain = road_fbm(uv * 2.6);
		float coarse = road_fbm(uv * 0.35 + vec2(17.0, 3.0));
		// Remendo de manutencao: mancha grande, mais clara e mais lisa.
		float patch = smoothstep(0.58, 0.74, road_fbm(uv * 0.14 + vec2(41.0, 9.0)));
		albedo = mix(albedo, asphalt_color * (0.82 + coarse * 0.42), 0.85);
		albedo = mix(albedo, patch_color, patch * 0.7);
		// Trinca: crista fina de ruido, escura.
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(road_fbm(uv * 0.9 + vec2(7.0, 23.0)) - 0.5));
		albedo *= 1.0 - crack * 0.45;
		albedo *= 0.92 + grain * 0.16;
		roughness = clamp(0.92 - patch * 0.2 + (grain - 0.5) * 0.12, 0.35, 1.0);

		// Sarjeta: as bordas da pista acumulam sujeira e ficam mais escuras.
		float edge = smoothstep(lane_half_width * 0.72, lane_half_width, abs(local_pos.x));
		albedo *= 1.0 - edge * 0.35;

		// Faixa central tracejada, gasta pelo uso (o ruido come pedacos dela).
		float center = 1.0 - smoothstep(0.06, 0.13, abs(local_pos.x));
		float dash = step(fract(local_pos.y / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));
		float wear = smoothstep(0.35, 0.75, road_fbm(uv * 1.7 + vec2(63.0, 5.0)));
		albedo = mix(albedo, lane_color, center * dash * wear * 0.85);
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
