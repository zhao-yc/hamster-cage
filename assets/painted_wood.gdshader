shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec3 wood = texture(grain, UV).rgb;
	float grain_value = dot(wood, vec3(0.3, 0.59, 0.11));
	ALBEDO = tint.rgb * mix(0.78, 1.08, grain_value);
	ROUGHNESS = 0.72;
	SPECULAR = 0.22;
}
