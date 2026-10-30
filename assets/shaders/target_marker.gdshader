shader_type spatial;
// Character shaders sample depth and render after opaque geometry. Draw the
// marker later, testing the opaque scene explicitly rather than character depth.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 marker_color : source_color = vec4(1.0, 0.72, 0.12, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// Godot 4.7 reverse-Z: larger depth is closer. Walls and floors still hide
	// the actual marker plane; sprites do not enter this opaque depth texture.
	if (FRAGCOORD.z + 0.00001 < texture(scene_depth, SCREEN_UV).r) { discard; }
	ALBEDO = marker_color.rgb;
	ALPHA = marker_color.a;
}
