shader_type spatial;
render_mode diffuse_burley;
uniform vec4 tint : source_color = vec4(1.0);
uniform float seed_kind = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	// 釉面细点和谷物纵纹跟随模型 UV，食物减少时纹路仍附着在各颗种子上。
	float fleck = step(0.976, hash(floor(UV * 330.0)));
	vec3 color = tint.rgb * (1.0 - fleck * 0.24);
	if (seed_kind > 0.5) {
		float stripes = pow(abs(sin(UV.x * 25.1327)), 10.0);
		color *= mix(0.83, 1.08, stripes);
		if (seed_kind > 1.5) color = mix(color, vec3(0.57, 0.46, 0.31), stripes * 0.55);
	}
	ALBEDO = color;
	ROUGHNESS = seed_kind > 0.5 ? 0.72 : 0.40;
	SPECULAR = 0.25;
}
