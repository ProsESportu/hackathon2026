shader_type spatial;
uniform sampler2D shadow_mask2d:source_color,repeat_enable,filter_linear;
const float barrier_value=0.001;

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}
void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float lit_intensity=smoothstep(0.0,0.5,NdotL*ATTENUATION);
	vec3 light_col=lit_intensity * LIGHT_COLOR / PI;
	
	ALPHA=0.4-light_col.r*10.0;
	vec3 color = texture(shadow_mask2d,UV).rgb;
	if(color.r>0.1)DIFFUSE_LIGHT=color;
}