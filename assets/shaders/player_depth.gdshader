shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite_sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float body_radius = 0.3;
uniform float body_height = 1.8;
// Optional enemy tint. Zero preserves the player's existing presentation.
uniform vec4 attack_warning_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float attack_warning_strength : hint_range(0.0, 1.0) = 0.0;
varying vec3 local_point;
varying vec3 feet_world;
varying vec3 horizontal_right;

void vertex() {
	local_point = VERTEX;
	feet_world = MODEL_MATRIX[3].xyz;
	horizontal_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	// Keep the same camera-facing image and foot pivot as AnimatedSprite3D.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec4 pixel = texture(sprite_sheet, UV);
	if (pixel.a < 0.5) { discard; }
	ALBEDO = mix(pixel.rgb, attack_warning_color.rgb, clamp(attack_warning_strength * attack_warning_color.a, 0.0, 1.0));
	// Depth comes from an upright cross-section inside the actual capsule.
	// Screen position, image size and alpha silhouette remain untouched.
	float height = clamp(local_point.y, 0.001, body_height - 0.001);
	float cap = max(body_radius - height, height - (body_height - body_radius));
	float radius = sqrt(max(body_radius * body_radius - max(cap, 0.0) * max(cap, 0.0), 0.0));
	vec3 proxy = feet_world + vec3(0.0, height, 0.0) + horizontal_right * clamp(local_point.x, -radius, radius);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(proxy, 1.0);
	float depth = clip.z / clip.w;
	depth = CLIP_SPACE_FAR == -1.0 ? depth * 0.5 + 0.5 : depth;
	vec2 proxy_uv = clip.xy / clip.w * 0.5 + 0.5;
	float blocker = texture(scene_depth, proxy_uv).r;
	if (depth + 0.00001 < blocker) { discard; }
	// Resolve silhouette overhang using the same visible body sample, not an
	// unconditional on-top sprite. A wall in front of the body still occludes it.
	DEPTH = max(depth, texture(scene_depth, SCREEN_UV).r + 0.000001);
}
