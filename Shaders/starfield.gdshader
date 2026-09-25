shader_type canvas_item;
render_mode unshaded;

uniform float pixel_resolution : hint_range(90.0, 360.0, 1.0) = 180.0;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 px = floor(UV * pixel_resolution);
    float h = hash21(px);
    float star = step(0.9905, h);
    float bright = step(0.9984, h);

    vec3 bg_top = vec3(0.002, 0.004, 0.012);
    vec3 bg_bottom = vec3(0.004, 0.009, 0.022);
    vec3 col = mix(bg_top, bg_bottom, UV.y);
    col += vec3(0.12, 0.17, 0.22) * star;
    col += vec3(0.24, 0.27, 0.31) * bright;
    COLOR = vec4(col, 1.0);
}
