shader_type spatial;
render_mode unshaded, cull_disabled;
#include "actor_attachment_depth.gdshaderinc"

void fragment() {
	vec4 pixel = texture(sprite_sheet, UV);
	if (pixel.a < 0.5) { discard; }
	ALBEDO = pixel.rgb;
	DEPTH = attachment_depth(PROJECTION_MATRIX, VIEW_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, SCREEN_UV, CLIP_SPACE_FAR);
}
