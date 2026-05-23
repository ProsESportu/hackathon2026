shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.7);
uniform float border_size = 0.25;
uniform float softness = 0.5;

void fragment() {
    vec2 uv = UV;

    float dist = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );

    float border = 1.0- smoothstep(
        border_size,
        border_size + softness,
        dist
    );

    COLOR.rgb = COLOR.rgb;
    COLOR.a = border * border_color.a;
}