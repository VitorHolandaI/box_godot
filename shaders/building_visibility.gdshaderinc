// Visibilidade compartilhada dos materiais de edificio (paredes, lajes, moveis,
// escadas e vidros). Mantem somente o andar do jogador quando ele esta dentro do
// predio, corta as paredes desse andar na altura SECTION_CUT_HEIGHT (vista de
// planta com altura) e abre o recorte entre a camera e o jogador quando ele esta
// na rua. No passe de sombra a camera e a luz, entao a posicao do jogador vem do
// uniform global interior_focus_position, publicado pela camera local principal.

uniform float cutout_radius : hint_range(0.3, 6.0) = 3.0;
uniform float occlusion_epsilon : hint_range(0.1, 2.0) = 0.5;
uniform float floor_height : hint_range(1.0, 6.0) = 2.8;
uniform bool ceiling_cutout = false;
uniform vec3 camera_offset = vec3(0.0, 19.0, 17.1);
uniform bool use_building_bounds = false;
uniform vec3 building_min = vec3(0.0);
uniform vec3 building_max = vec3(0.0);
// Escadas ficam inteiras: cortadas a meia altura o lance parece quebrado.
uniform bool section_cut_exempt = false;

global uniform vec3 interior_focus_position;

const float SECTION_CUT_HEIGHT = 1.35;
// Pes do jogador ficam ~1.17 m abaixo da origem; o andar so troca perto do topo
// do lance (0.9 m antes da laje) para nao sumir o chao no meio da subida.
const float PLAYER_ORIGIN_TO_FEET = 1.17;
const float FLOOR_SWITCH_LEAD = 0.9;

varying vec3 world_position;

vec3 visibility_player_position(vec3 camera_position, vec3 camera_forward) {
	float player_height = camera_position.y - camera_offset.y;
	vec3 view_direction = camera_forward.y > 0.0 ? -camera_forward : camera_forward;
	float camera_ray_y = min(view_direction.y, -0.001);
	float camera_to_floor = (player_height - camera_position.y) / camera_ray_y;
	return camera_position + view_direction * camera_to_floor;
}

bool visibility_player_inside(vec3 player_position) {
	return use_building_bounds &&
		player_position.x >= building_min.x && player_position.x <= building_max.x &&
		player_position.y >= building_min.y && player_position.y <= building_max.y &&
		player_position.z >= building_min.z && player_position.z <= building_max.z;
}

float visibility_floor_base(vec3 player_position) {
	float feet_above_base = player_position.y - PLAYER_ORIGIN_TO_FEET - building_min.y;
	float floor_index = floor((feet_above_base + FLOOR_SWITCH_LEAD) / floor_height);
	return building_min.y + max(floor_index, 0.0) * floor_height;
}

// Verdadeiro quando o fragmento deve sumir para quem esta dentro do predio.
bool visibility_hidden_indoors(vec3 player_position) {
	if (!visibility_player_inside(player_position)) {
		return false;
	}
	float floor_base = visibility_floor_base(player_position);
	float height_in_floor = world_position.y - floor_base;
	if (height_in_floor < -0.12 || height_in_floor > floor_height - 0.1) {
		return true;
	}
	return !section_cut_exempt && height_in_floor > SECTION_CUT_HEIGHT;
}

// Recorte em tubo entre camera e jogador, usado so na rua.
bool visibility_hidden_by_camera_tube(vec3 camera_position, vec3 player_position, out float rim) {
	rim = 0.0;
	if (visibility_player_inside(player_position)) {
		return false;
	}
	vec3 camera_to_player = player_position - camera_position;
	float player_distance = length(camera_to_player);
	vec3 camera_direction = camera_to_player / max(player_distance, 0.001);
	float segment_position = dot(world_position - camera_position, camera_to_player) / max(dot(camera_to_player, camera_to_player), 0.001);
	vec3 closest_point = camera_position + camera_to_player * clamp(segment_position, 0.0, 1.0);
	float fragment_depth = dot(world_position - camera_position, camera_direction);
	float dist_to_segment = distance(world_position, closest_point);
	bool occluding = fragment_depth > 0.0 && fragment_depth < player_distance - occlusion_epsilon;
	if (occluding && dist_to_segment < cutout_radius) {
		return true;
	}
	if (occluding && dist_to_segment < cutout_radius + 0.45) {
		rim = 1.0 - (dist_to_segment - cutout_radius) / 0.45;
	}
	return false;
}

// Verdadeiro quando o fragmento deve ser descartado. Built-ins de camera sao
// recebidos por parametro porque so existem dentro de fragment().
// `front_facing` falso so vale como tampa do corte quando o jogador esta dentro;
// na rua as faces de tras seguem invisiveis, como antes do cull_disabled.
bool visibility_should_discard(vec3 camera_position, vec3 camera_forward, bool in_shadow_pass, bool front_facing, out float rim) {
	rim = 0.0;
	vec3 player_position = in_shadow_pass
		? interior_focus_position
		: visibility_player_position(camera_position, camera_forward);
	if (visibility_hidden_indoors(player_position)) {
		return true;
	}
	if (!in_shadow_pass && !front_facing && !visibility_player_inside(player_position)) {
		return true;
	}
	bool hidden = !in_shadow_pass && visibility_hidden_by_camera_tube(camera_position, player_position, rim);
	rim = front_facing ? rim : 0.0;
	return hidden;
}
