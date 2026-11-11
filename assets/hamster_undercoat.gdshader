shader_type spatial;
render_mode diffuse_burley;
void fragment() {
	float frequency = 1900.0;
	float strand = sin(UV.x * frequency + sin(UV.y * 52.0) * 1.7);
	float fade = 1.0 - smoothstep(0.4, 2.0, fwidth(UV.x * frequency));
	ALBEDO = COLOR.rgb * (0.97 + strand * fade * 0.025);
	ROUGHNESS = 0.94;
	SPECULAR = 0.10;
}
