shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, fog_disabled;
uniform vec4 flash_color : source_color = vec4(1.0,0.96,0.82,1.0);
uniform float flash_strength : hint_range(0.0,1.0) = 0.55;
uniform bool use_texture_alpha = false;
uniform sampler2D source_texture : source_color, filter_nearest;
void fragment() {
	float mask = use_texture_alpha ? texture(source_texture, UV).a : 1.0;
	if (mask < 0.01) { discard; }
	ALBEDO = flash_color.rgb;
	ALPHA = mask * flash_strength;
}
