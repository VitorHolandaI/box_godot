shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.48, 0.25, 0.18, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float material_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float cutout_radius : hint_range(0.3, 3.0) = 0.9;
uniform float occlusion_epsilon : hint_range(0.1, 2.0) = 0.5;
uniform float floor_height : hint_range(1.0, 6.0) = 2.8;
uniform bool ceiling_cutout = false;
uniform vec3 camera_offset = vec3(0.0, 19.0, 17.1);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 camera_to_player = -camera_offset;
	vec3 player_position = CAMERA_POSITION_WORLD - camera_offset;
	float player_distance = length(camera_to_player);
	vec3 camera_direction = camera_to_player / player_distance;

	float segment_length_squared = dot(camera_to_player, camera_to_player);
	float segment_position = dot(world_position - CAMERA_POSITION_WORLD, camera_to_player) / segment_length_squared;
	vec3 closest_point = CAMERA_POSITION_WORLD + camera_to_player * clamp(segment_position, 0.0, 1.0);

	float fragment_depth = dot(world_position - CAMERA_POSITION_WORLD, camera_direction);
	float dist_to_segment = distance(world_position, closest_point);
	bool within_tube = dist_to_segment < cutout_radius;
	bool occluding = fragment_depth > 0.0 && fragment_depth < player_distance - occlusion_epsilon;

	float player_floor_base = floor(player_position.y / floor_height) * floor_height;
	bool player_floor = world_position.y >= player_floor_base - 0.12 && world_position.y <= player_floor_base + floor_height + 0.12;
	bool can_cutout = player_floor || (ceiling_cutout && world_position.y > player_floor_base + floor_height);
	if (within_tube && occluding && can_cutout) {
		discard;
	}

	if (occluding && dist_to_segment >= cutout_radius && dist_to_segment < cutout_radius + 0.45) {
		float rim = 1.0 - (dist_to_segment - cutout_radius) / 0.45;
		EMISSION = vec3(0.18, 0.55, 0.95) * rim * 1.5;
	}

	if (use_texture) {
		ALBEDO = texture(albedo_texture, UV).rgb * base_color.rgb;
	} else {
		ALBEDO = base_color.rgb;
	}
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
}
