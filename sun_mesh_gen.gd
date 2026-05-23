# AnimatedSunProcedural.gd
# Fully self-contained Sun generator with animated shaders and pulse
# Now renders in the editor
@tool
extends Node3D

@export var pulse_min_interval : float = 3.5
@export var pulse_max_interval : float = 7.5
@export var pulse_scale_factor : float = 1.07
@export var pulse_half_duration : float = 4.2

var sun_mesh : MeshInstance3D
var time_accum : float = 0.0
var next_pulse_at : float = 0.0
var shader_materials : Array[ShaderMaterial] = []

func _enter_tree() -> void:
	# Ensure the sun is visible in editor
	_create_sun_mesh()
	_collect_materials()
	_schedule_next_pulse()

func _process(delta: float) -> void:
	# Skip pulse timing in editor
	if Engine.is_editor_hint():
		time_accum += delta
		for mat in shader_materials:
			if mat:
				mat.set_shader_parameter("time", time_accum)
		return
	
	time_accum += delta
	for mat in shader_materials:
		if mat:
			mat.set_shader_parameter("time", time_accum)
	if Time.get_unix_time_from_system() > next_pulse_at:
		_trigger_pulse()
		_schedule_next_pulse()

# ─── Single Sun Mesh ──────────────────────────────
func _create_sun_mesh() -> void:
	if sun_mesh:
		return
	
	sun_mesh = MeshInstance3D.new()
	sun_mesh.mesh = SphereMesh.new()
	var shader = Shader.new()
	shader.code = _sun_core_shader_code()
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", Color(1.0, 0.92, 0.38))
	
	sun_mesh.material_override = mat
	shader_materials.append(mat)
	
	add_child(sun_mesh)
	if Engine.is_editor_hint():
		sun_mesh.visible = true
	print("Created single Sun mesh (editor ready)")

# ─── Pulsing ──────────────────────────────
func _trigger_pulse() -> void:
	var tween = create_tween()
	var base_scale = sun_mesh.scale
	var peak_scale = base_scale * pulse_scale_factor
	tween.tween_property(sun_mesh, "scale", peak_scale, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sun_mesh, "scale", base_scale, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _schedule_next_pulse() -> void:
	var delay = randf_range(pulse_min_interval, pulse_max_interval)
	next_pulse_at = Time.get_unix_time_from_system() + delay

func _collect_materials() -> void:
	if sun_mesh and sun_mesh.material_override is ShaderMaterial:
		shader_materials = [sun_mesh.material_override]

# ────────────────────────────────────────────────
# Shaders
# ────────────────────────────────────────────────
func _sun_core_shader_code() -> String:
	return """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float time;
varying vec3 vert_pos;
varying vec3 vNormal;

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x*34.0)+1.0)*x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0/6.0, 1.0/3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i  = floor(v + dot(v, C.yyy) );
    vec3 x0 =   v - i + dot(i, C.xxx) ;
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min( g.xyz, l.zxy );
    vec3 i2 = max( g.xyz, l.zxy );
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289(i);
    vec4 p = permute( permute( permute( 
               i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
             + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
             + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));
    float n_ = 0.142857142857; vec3  ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z); vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy; vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4( x.xy, y.xy ); vec4 b1 = vec4( x.zw, y.zw );
    vec4 s0 = floor(b0)*2.0 + 1.0; vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ; vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;
    vec3 p0 = vec3(a0.xy,h.x); vec3 p1 = vec3(a0.zw,h.y);
    vec3 p2 = vec3(a1.xy,h.z); vec3 p3 = vec3(a1.zw,h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

float fbm(vec3 p) {
    float v = 0.0; float a = 0.9; vec3 shift = vec3(100.0);
    for (int i = 0; i < 8; ++i) { v += a * snoise(p); p = p * 2.0 + shift; a *= 0.9; }
    return v;
}

float fbmDetail(vec3 p) {
    float v = 0.0; float a = 0.9; vec3 shift = vec3(50.0);
    for (int i = 0; i < 8; ++i) { v += a * snoise(p); p = p * 3.0 + shift; a *= 0.9; }
    return v;
}

void vertex() {
    vert_pos = VERTEX;
    vNormal = NORMAL;
}

void fragment() {
    vec3 pos = vert_pos * 0.9 + time * -0.05;
    float n1 = fbm(pos); n1 = n1 * 2.0 + 0.9;
    float n2 = fbm(pos + vec3(40.0)); n2 = n2 * 0.9 + 0.9;
    float baseNoise = (n1 * 0.6 + n2 * 0.9); baseNoise = clamp(baseNoise, 0.0, 1.0);
    float detail = fbmDetail(pos * 5.0 + vec3(30.0));
    detail = detail * 0.5 + 0.5; baseNoise += detail * 0.15; baseNoise = clamp(baseNoise, 0.0, 1.0);
    vec3 viewDir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(vert_pos,1.0)).xyz);
    float rim = 1.0 - max(dot(vNormal, viewDir), 0.0); rim = pow(rim, 2.0);
    float glowFactor = rim;
    vec3 glowColor = vec3(1.0, 0.9, 0.6);
    vec3 radiantGlow = glowColor * glowFactor * 0.9;
    vec3 yellow = vec3(1.0, 0.55, 0.0);
    vec3 orange = vec3(1.0, 0.27, 0.0);
    vec3 red = vec3(0.8, 0.2, 0.0);
    vec3 color = mix(yellow, orange, baseNoise);
    color = mix(color, red, detail * 0.9);
    color += radiantGlow;
    ALBEDO = color;
    EMISSION = color * 0.5;
}
"""

func _atmosphere_shader_code(_has_glow: bool) -> String:
	return """
shader_type spatial;
render_mode unshaded, cull_front, blend_add;
uniform vec3 color_start : source_color;
uniform vec3 color_end : source_color;
uniform float glow_intensity = 1.5;
void fragment() {
    float dist = length(VERTEX) / 1.0;
    vec3 color = mix(color_start, color_end, dist);
    float intensity = pow(0.8 - dot(NORMAL, VIEW), 2.0);
    ALBEDO = color * intensity * glow_intensity;
    ALPHA = intensity * glow_intensity;
}
"""
