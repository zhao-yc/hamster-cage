shader_type spatial;

uniform vec4 skin_tint : source_color = vec4(0.85, 0.65, 0.54, 1.0);
uniform vec4 nail_tint : source_color = vec4(0.91, 0.74, 0.68, 1.0);

void fragment() {
	// UV.y 从指尖延伸到指根，指甲和细纹直接贴在弯曲的表面。
	float side = (UV.x - 0.25) * 6.2831853;
	float nail = 1.0 - smoothstep(0.90, 1.04, length(vec2(side / 0.81, (UV.y - 0.165) / 0.105)));
	float joint = UV.y - 0.40 + side * side * 0.024;
	float first_fold = joint / 0.010;
	float second_fold = (joint - 0.031) / 0.009;
	float folds = (1.0 - smoothstep(0.15, 0.93, abs(side))) *
		(0.12 * exp(-first_fold * first_fold) + 0.055 * exp(-second_fold * second_fold));
	float tip_warmth = 1.0 - smoothstep(0.07, 0.31, UV.y);
	vec3 skin = skin_tint.rgb * (1.0 - folds) * mix(vec3(1.0), vec3(1.02, 0.91, 0.88), tip_warmth);
	ALBEDO = mix(skin, nail_tint.rgb, nail);
	ALPHA = mix(0.52, 0.65, nail);
	ROUGHNESS = mix(0.72, 0.43, nail);
	SPECULAR = mix(0.29, 0.39, nail);
}
