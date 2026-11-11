shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool packed = false;
void fragment() {
	// 原照片只提供纤维明暗，避免暖光叠加照片的橙色后把整片垫料染黄。
	float fiber = dot(texture(grain, UV).rgb, vec3(0.3, 0.59, 0.11));
	float contrast = packed ? mix(0.60, 0.86, fiber) : mix(0.60, 0.82, fiber);
	// 木屑是无厚度的卷片，背面沿用朝上的纤维法线，避免翻面变成黑色三角。
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	ALBEDO = tint.rgb * contrast * (packed ? vec3(1.0) : COLOR.rgb);
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
}
