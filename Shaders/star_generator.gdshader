shader_type canvas_item;
render_mode unshaded;

uniform vec2 rotation_xy = vec2(0.0, 0.0);
uniform float seed : hint_range(0.0, 1000000.0) = 19.0;
uniform float pixel_resolution : hint_range(48.0, 256.0, 1.0) = 128.0;
uniform float planet_radius : hint_range(0.55, 0.95) = 0.78;
uniform vec3 core_color = vec3(1.00, 0.96, 0.70);
uniform vec3 mid_color = vec3(1.00, 0.80, 0.34);
uniform vec3 edge_color = vec3(0.99, 0.55, 0.14);
uniform vec3 glow_color = vec3(1.00, 0.68, 0.22);
uniform vec3 local_light_dir = vec3(-0.65, -0.25, 0.72);
uniform float lighting_strength : hint_range(0.0, 1.0) = 0.55;

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    float x00 = mix(n000, n100, f.x);
    float x10 = mix(n010, n110, f.x);
    float x01 = mix(n001, n101, f.x);
    float x11 = mix(n011, n111, f.x);
    float y0 = mix(x00, x10, f.y);
    float y1 = mix(x01, x11, f.y);
    return mix(y0, y1, f.z);
}

float fbm(vec3 p) {
    float value = 0.0;
    float amp = 0.56;
    value += noise3(p) * amp;
    p = p * 2.02 + vec3(7.7, 3.2, 11.1);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.03 + vec3(2.9, 9.1, 6.8);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.04 + vec3(12.2, 4.6, 5.4);
    amp *= 0.5;
    value += noise3(p) * amp;
    return value / 1.0325;
}

vec3 rotate_y(vec3 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 rotate_x(vec3 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

void fragment() {
    vec2 q_uv = (floor(UV * pixel_resolution) + 0.5) / pixel_resolution;
    vec2 p = (q_uv * 2.0 - 1.0) / planet_radius;
    float d = length(p);

    if (d > 1.0) {
        if (d <= 1.16) {
            float glow = 1.0 - smoothstep(1.0, 1.16, d);
            float alpha = floor(glow * 4.0) / 4.0;
            COLOR = vec4(glow_color * (0.42 + glow * 0.58), alpha * 0.76);
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 normal = normalize(vec3(p.x, p.y, z));
        vec3 sample_pos = rotate_y(normal, rotation_xy.x * 0.82);
        sample_pos = rotate_x(sample_pos, rotation_xy.y * 0.82);
        vec3 seed_offset = vec3(seed * 0.061, seed * 0.093, seed * 0.051);

        float swirl = fbm(sample_pos * 4.8 + seed_offset);
        float bands = 0.5 + 0.5 * sin((sample_pos.y + swirl * 0.22) * 15.0 + seed * 0.03);
        float plasma = fbm(sample_pos * 9.0 + seed_offset * 1.7 + vec3(5.0, 3.0, 12.0));
        float radial = 1.0 - (1.0 - z);

        vec3 base = mix(edge_color, mid_color, smoothstep(0.0, 1.0, radial));
        base = mix(base, core_color, smoothstep(0.50, 1.0, radial));
        base = mix(base, glow_color, bands * 0.20);
        base = mix(base, core_color, smoothstep(0.70, 0.97, plasma) * 0.20);
        float edge_heat = pow(1.0 - z, 1.6);
        base += glow_color * edge_heat * 0.18;

        vec3 ldir = normalize(local_light_dir);
        float diffuse = clamp(dot(sample_pos, ldir), 0.0, 1.0);
        float stepped = floor(diffuse * 4.0) / 3.0;
        stepped = clamp(stepped, 0.0, 1.0);
        float light_mix = 0.30 + stepped * 0.70;
        vec3 lit = mix(base, base * light_mix, lighting_strength);
        COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), 1.0);
    }
}
