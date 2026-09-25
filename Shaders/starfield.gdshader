shader_type canvas_item;
render_mode unshaded;

// Chunkier pixel-art stars: each star is one 4x4 logical pixel cell.
// This restores the readable size of the earlier star-field versions while
// keeping every star square at 16:9 instead of stretching UV cells.
uniform float star_pixel_size : hint_range(2.0, 8.0, 1.0) = 4.0;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 cell = floor(FRAGCOORD.xy / star_pixel_size);
    float h = hash21(cell);

    // Roughly the same visual density as the older 180-cell shader.
    float star = step(0.9948, h);
    float bright = step(0.9990, h);
    float warm = step(0.99972, h);

    vec3 bg_top = vec3(0.0012, 0.0024, 0.0068);
    vec3 bg_bottom = vec3(0.0024, 0.0052, 0.0125);
    vec3 col = mix(bg_top, bg_bottom, UV.y);

    col += vec3(0.20, 0.27, 0.34) * star;
    col += vec3(0.52, 0.65, 0.76) * bright;
    col += vec3(0.88, 0.86, 0.72) * warm;

    COLOR = vec4(col, 1.0);
}
