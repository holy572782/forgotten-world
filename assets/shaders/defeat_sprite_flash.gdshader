shader_type canvas_item;
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	COLOR = vec4(mix(pixel.rgb, flash_color.rgb, flash_strength), pixel.a);
}
