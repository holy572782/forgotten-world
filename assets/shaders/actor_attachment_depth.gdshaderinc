// Shared owner depth for opaque weapon and translucent effect.
uniform sampler2D sprite_sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float body_radius = 0.3;
uniform float body_height = 1.8;
uniform float ground_clearance = 0.015;
uniform float layer_depth_bias = 0.000002;
uniform bool owner_floor_occluded = false;
varying vec3 local_point;
varying vec3 feet_world;
varying vec3 horizontal_right;

void vertex() {
	local_point = VERTEX;
	feet_world = MODEL_MATRIX[3].xyz;
	horizontal_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float attachment_depth(mat4 projection, mat4 view, mat4 inverse_projection, mat4 inverse_view, vec2 screen_uv, float clip_space_far) {
	float height = clamp(local_point.y, 0.001, body_height - 0.001);
	float cap = max(body_radius - height, height - (body_height - body_radius));
	float radius = sqrt(max(body_radius * body_radius - max(cap, 0.0) * max(cap, 0.0), 0.0));
	vec3 proxy = feet_world + vec3(0.0, height, 0.0) + horizontal_right * clamp(local_point.x, -radius, radius);
	vec4 clip = projection * view * vec4(proxy, 1.0);
	float depth = clip.z / clip.w;
	depth = clip_space_far == -1.0 ? depth * 0.5 + 0.5 : depth;
	float screen_depth = texture(scene_depth, screen_uv).r;
	float ndc_z = clip_space_far == -1.0 ? screen_depth * 2.0 - 1.0 : screen_depth;
	vec4 view_point = inverse_projection * vec4(screen_uv * 2.0 - 1.0, ndc_z, 1.0);
	vec3 world_point = (inverse_view * vec4(view_point.xyz / max(view_point.w, 0.0000001), 1.0)).xyz;
	bool ground = screen_depth > 0.0 && world_point.y <= feet_world.y + ground_clearance;
	// A solid terrain wall hiding the owner's feet must not leak the blade
	// onto the floor in front of that wall. Enemy bodies do not set this flag.
	if (ground && owner_floor_occluded) { discard; }
	// Floor/lower terrain below the owner's feet must not cut its 2D canvas.
	// Higher surfaces/nearer enemies retain per-pixel depth. Do not reject an
	// entire overhanging blade just because an enemy covers its owner's feet.
	if (!ground && depth + 0.00001 < screen_depth) { discard; }
	return ground ? max(depth + layer_depth_bias, screen_depth + layer_depth_bias) : depth + layer_depth_bias;
}
