shader_type spatial;
// Faces de tras aparecem como "tampa" escura onde a parede foi cortada.
render_mode cull_disabled;

#include "res://shaders/building_visibility.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.48, 0.25, 0.18, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float material_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;

const vec3 SECTION_CAP_COLOR = vec3(0.13, 0.12, 0.11);

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = 0.0;
	if (visibility_should_discard(CAMERA_POSITION_WORLD, CAMERA_DIRECTION_WORLD, IN_SHADOW_PASS, FRONT_FACING || IN_SHADOW_PASS, rim)) {
		discard;
	}
	vec3 albedo = use_texture ? texture(albedo_texture, UV).rgb * base_color.rgb : base_color.rgb;
	if (!FRONT_FACING) {
		// Interior de uma caixa cortada: pinta como secao macica.
		albedo = SECTION_CAP_COLOR;
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	ALBEDO = albedo;
	EMISSION = vec3(0.18, 0.55, 0.95) * rim * 1.5;
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
}
