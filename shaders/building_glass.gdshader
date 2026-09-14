shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#include "res://shaders/building_visibility.gdshaderinc"

uniform vec4 glass_color : source_color = vec4(0.66, 0.82, 0.92, 0.32);

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = 0.0;
	if (visibility_should_discard(CAMERA_POSITION_WORLD, CAMERA_DIRECTION_WORLD, false, true, rim)) {
		discard;
	}
	ALBEDO = glass_color.rgb;
	ALPHA = glass_color.a;
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
}
