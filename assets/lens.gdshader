shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	// 轻微前景景深落在最下沿，中央活动区保持清晰。
	float edge = smoothstep(0.82, 1.0, SCREEN_UV.y);
	float corners = smoothstep(0.27, 0.52, abs(SCREEN_UV.x - 0.5));
	float blur = edge * (0.5 + corners) * 1.1;
	vec3 color = textureLod(screen_texture, SCREEN_UV, blur).rgb;
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, 0.88);
	float vignette = dot(SCREEN_UV - 0.5, SCREEN_UV - 0.5);
	COLOR = vec4(color * (1.0 - vignette * 0.055), 1.0);
}
