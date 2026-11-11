shader_type spatial;
render_mode cull_disabled, diffuse_burley, alpha_to_coverage;
void fragment() {
	// 每束含八根弯曲细毛，根部密、末端细，覆盖率由 MSAA 平滑。
	float id = floor(UV.x * 8.0);
	float phase = sin(id * 17.31) * 0.5 + 0.5;
	float center = fract(UV.x * 8.0) - 0.5 + sin(UV.y * 3.7 + id * 0.8) * UV.y * 0.17;
	float width = mix(0.37, 0.035, UV.y);
	float reach = 0.76 + phase * 0.24;
	float alpha = (1.0 - smoothstep(width * 0.50, width, abs(center))) * (1.0 - smoothstep(reach - 0.12, reach, UV.y));
	ALBEDO = COLOR.rgb * mix(0.91, 1.04, smoothstep(0.0, 0.85, UV.y));
	ROUGHNESS = 0.88;
	SPECULAR = 0.12;
	RIM = 0.08;
	RIM_TINT = 0.65;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.40;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(128.0, 256.0);
}
