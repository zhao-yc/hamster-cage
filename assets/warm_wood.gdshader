shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 wood = texture(grain, vec2((world_point.x + 8.0) / 16.0, world_point.y / 6.0)).rgb * tint.rgb;
	// 固定窗光落在后壁，暖色光斑只影响材质明暗。
	float ribbon = smoothstep(-0.50, 0.90, sin((world_point.x + world_point.y * 0.58) * 3.2));
	float left = 1.0 - smoothstep(-5.0, -0.4, world_point.x);
	float sunlight = ribbon * left * smoothstep(0.2, 1.6, world_point.y);
	ALBEDO = wood * (0.91 + sunlight * 0.15);
	EMISSION = wood * vec3(1.0, 0.87, 0.65) * sunlight * 0.20;
	ROUGHNESS = 0.90;
}
