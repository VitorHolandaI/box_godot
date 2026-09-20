shader_type spatial;
// Faces de tras aparecem como "tampa" escura onde a parede foi cortada.
render_mode cull_disabled;

#include "res://shaders/building_visibility.gdshaderinc"

// Normal em espaco de mundo. `NORMAL` no fragment() e view space (o vertex
// entrega em model space); usa-la direto fazia a escolha do eixo da textura
// depender da rotacao da camera e a parede "nadar" ao olhar em volta.
varying vec3 world_normal;

uniform vec4 base_color : source_color = vec4(0.48, 0.25, 0.18, 1.0);
// A textura e projetada em metros no mundo: as UVs passam de 1 e a superficie
// e vista em angulo raso, entao precisa de repeat + mipmap anisotropico para
// nao serrilhar no fundo (mipmaps desligados no .import anulam o filtro).
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
// Tamanho real de uma repeticao da textura. A projecao usa a superficie no
// mundo, nao UV de BoxMesh, para cada painel de parede manter a mesma escala.
uniform float texture_meters : hint_range(0.1, 16.0) = 1.0;
uniform float material_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
// Detalhe procedural da fachada. Em 0 o material volta a ser cor chapada
// (moveis pequenos e pecas onde a sujeira em escala de metro nao faz sentido).
uniform float detail_strength : hint_range(0.0, 1.0) = 1.0;
// Largura do modulo vertical da fachada, em metros: o vinco entre paineis.
uniform float panel_width : hint_range(0.4, 6.0) = 1.35;
// Altura da fiada de telha, em metros. Em 0 a peca nao tem fiada (paredes,
// moveis); o telhado liga para o plano inclinado parar de ser uma chapa.
uniform float shingle_period : hint_range(0.0, 2.0) = 0.0;

const vec3 SECTION_CAP_COLOR = vec3(0.13, 0.12, 0.11);
// Altura onde a sujeira de respingo da rua deixa de subir pela parede.
const float SPLASH_HEIGHT = 2.2;

float detail_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float detail_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(detail_hash(i), detail_hash(i + vec2(1.0, 0.0)), u.x),
		mix(detail_hash(i + vec2(0.0, 1.0)), detail_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Duas oitavas bastam: a parede so precisa parar de ser uma chapa lisa.
float detail_fbm(vec2 p) {
	return detail_noise(p) * 0.65 + detail_noise(p * 2.7 + vec2(19.3, 7.1)) * 0.35;
}

// Vinco escuro perto de cada multiplo de `period`, com `softness` metros de
// transicao. Serve tanto para a junta de andar quanto para o painel vertical.
float seam(float value, float period, float softness) {
	float distance_to_seam = abs(fract(value / period) - 0.5) * period;
	return 1.0 - smoothstep(0.0, softness, distance_to_seam);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float rim = 0.0;
	if (visibility_should_discard(CAMERA_POSITION_WORLD, CAMERA_DIRECTION_WORLD, IN_SHADOW_PASS, FRONT_FACING || IN_SHADOW_PASS, rim)) {
		discard;
	}
	vec3 albedo = base_color.rgb;
	float roughness = material_roughness;
	if (detail_strength > 0.001) {
		// Coordenada da superficie sem depender de UV: as caixas procedurais
		// nao tem mapeamento util. A parede usa o plano horizontal que ela
		// enfrenta; piso e telhado usam o plano XZ.
		vec3 surface_normal = normalize(world_normal);
		float wall_facing = 1.0 - min(abs(surface_normal.y), 1.0);
		vec2 along = mix(world_position.xz, vec2(
			mix(world_position.x, world_position.z, step(0.5, abs(surface_normal.x))),
			world_position.y
		), wall_facing);
		if (use_texture) {
			albedo = texture(albedo_texture, along / texture_meters).rgb * base_color.rgb;
		}

		float grime = detail_fbm(along * 0.55);
		float speckle = detail_fbm(along * 3.1 + vec2(31.0, 11.0));
		// Sujeira que sobe da rua e clareamento de sol no alto da parede.
		float splash = 1.0 - smoothstep(0.0, SPLASH_HEIGHT, world_position.y);
		float weather = mix(grime, speckle, 0.35);

		// Junta de andar e modulo vertical: e o que faz a caixa virar predio.
		float floor_seam = seam(world_position.y, max(floor_height, 0.5), 0.045) * wall_facing;
		float panel_seam = seam(along.x, panel_width, 0.02) * wall_facing;
		float seams = max(floor_seam, panel_seam * 0.55);
		if (shingle_period > 0.001) {
			// Fiada de telha: linha horizontal no plano inclinado, mais forte
			// quanto mais o plano estiver deitado.
			float slope = 1.0 - wall_facing;
			seams = max(seams, seam(world_position.y, shingle_period, 0.012) * slope * 0.8);
		}

		float shade = 1.0
			- weather * 0.16
			- splash * wall_facing * 0.14
			- seams * 0.30;
		albedo *= mix(1.0, shade, detail_strength);
		// Aspereza irregular: sem isso a luz bate igual na parede inteira e
		// tudo volta a parecer plastico.
		roughness = clamp(roughness + (weather - 0.5) * 0.22 * detail_strength, 0.05, 1.0);
	}
	else if (use_texture) {
		vec2 fallback_uv = world_position.xz / texture_meters;
		albedo = texture(albedo_texture, fallback_uv).rgb * base_color.rgb;
	}
	if (!FRONT_FACING) {
		// Interior de uma caixa cortada: pinta como secao macica. Com o cutout
		// desligado (primeira pessoa) a face de tras e parede normal.
		albedo = cutout_enabled ? SECTION_CAP_COLOR : albedo;
		// NORMAL e inout em view space: converte o "para cima" do mundo de
		// volta, senao a tampa de corte e iluminada como se apontasse para a
		// camera.
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
	ALBEDO = albedo;
	EMISSION = vec3(0.18, 0.55, 0.95) * rim * 1.5;
	ROUGHNESS = roughness;
	METALLIC = material_metallic;
}
