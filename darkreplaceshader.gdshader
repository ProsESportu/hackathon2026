shader_type spatial;
uniform sampler2D shadow_mask2d:source_color,repeat_enable,filter_linear;
void fragment(){
	//ALBEDO =vec3(0.0);
}
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
	//toon light, relatively flat color, no smooth blur edge
	vec3 light_col=lit_intensity * LIGHT_COLOR / PI;
	//DIFFUSE_LIGHT=light_col;
	if(light_col.r>0.0){
		ALPHA=0.0;
	}else{
		//DIFFUSE_LIGHT=vec3(1.0);
		vec3 color = texture(shadow_mask2d,UV).rgb;
		if(color.r>0.1)DIFFUSE_LIGHT=color;
	}
}