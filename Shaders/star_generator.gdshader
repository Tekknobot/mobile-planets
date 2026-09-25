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
uniform float blackhole_dissolve : hint_range(0.0, 1.0) = 0.0;

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453123);
}

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

            float corona_noise = fbm(vec3(q_uv * 8.0, seed * 0.021));
            float corona_variation = mix(0.82, 1.18, corona_noise);

            float alpha = floor(glow * 4.0) / 4.0;
            vec3 corona = glow_color * (0.38 + glow * 0.62) * corona_variation;

            COLOR = vec4(corona, alpha * 0.76);
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 normal = normalize(vec3(p.x, p.y, z));

        vec3 sample_pos = rotate_y(normal, rotation_xy.x * 0.82);
        sample_pos = rotate_x(sample_pos, rotation_xy.y * 0.82);

        vec3 seed_offset = vec3(seed * 0.061, seed * 0.093, seed * 0.051);

        float seed_a = hash11(seed * 0.17 + 3.1);
        float seed_b = hash11(seed * 0.29 + 7.3);
        float seed_c = hash11(seed * 0.41 + 11.7);
        float seed_d = hash11(seed * 0.53 + 19.4);

        float radial = z;

        // Large-scale distortion to stop stars from feeling too symmetrical.
        float macro_warp = fbm(sample_pos * (2.8 + seed_a * 1.8) + seed_offset * 0.7);
        float warp_y = sample_pos.y
            + (macro_warp - 0.5) * (0.38 + seed_b * 0.28)
            + sin(sample_pos.x * (3.5 + seed_c * 4.0) + seed * 0.01) * 0.06;

        // Layered banding with seed-driven frequency.
        float band1 = 0.5 + 0.5 * sin(warp_y * (10.0 + seed_a * 10.0) + seed * 0.031);
        float band2 = 0.5 + 0.5 * sin(warp_y * (18.0 + seed_b * 14.0) + sample_pos.x * (2.0 + seed_c * 4.5));
        float band3 = 0.5 + 0.5 * sin(warp_y * (28.0 + seed_d * 10.0) - sample_pos.z * 4.5);
        float bands = band1 * 0.46 + band2 * 0.36 + band3 * 0.18;

        // Fine solar granulation.
        float granulation = fbm(sample_pos * (16.0 + seed_a * 8.0) + seed_offset * 2.7);
        float grain = noise3(sample_pos * (32.0 + seed_b * 12.0) + seed_offset * 4.1);

        // Hot plasma cells.
        float hot_cells = fbm(sample_pos * (11.0 + seed_c * 5.0) + vec3(13.0, 4.0, 8.0) + seed_offset);
        hot_cells = smoothstep(0.64, 0.86, hot_cells);

        // Darker sunspot / cooler regions.
        float spot_field = fbm(sample_pos * (7.0 + seed_d * 5.0) + vec3(4.0, 17.0, 2.0) + seed_offset * 1.2);
        float spots = smoothstep(0.74, 0.90, spot_field);

        // Extra asymmetry.
        float hemispheric_shift = smoothstep(-0.2, 0.8, sample_pos.x * (seed_a - 0.5) + sample_pos.z * (seed_b - 0.5));

        vec3 base = mix(edge_color, mid_color, smoothstep(0.0, 1.0, radial));
        base = mix(base, core_color, smoothstep(0.38, 1.0, radial));

        // Band color shaping.
        base = mix(base, glow_color, bands * 0.16);
        base = mix(base, core_color, smoothstep(0.68, 0.98, granulation) * 0.22);

        // Hot cells brighten toward the core palette.
        base = mix(base, core_color * 1.05, hot_cells * 0.28);

        // Spots cool and darken local areas.
        base = mix(base, edge_color * 0.55, spots * 0.30);

        // Fine breakup.
        base += (grain - 0.5) * 0.10;
        base += (granulation - 0.5) * 0.12;

        // Slight hemisphere bias to avoid evenness.
        base *= mix(0.92, 1.08, hemispheric_shift);

        // Limb heating.
        float edge_heat = pow(1.0 - z, 1.6);
        base += glow_color * edge_heat * (0.14 + seed_c * 0.10);

        // Lighting.
        vec3 ldir = normalize(local_light_dir);
        float daylight = clamp((dot(sample_pos, ldir) + 0.25) / 1.25, 0.0, 1.0);
        float stepped = floor(daylight * 4.999) / 4.0;
        stepped = clamp(stepped, 0.0, 1.0);

        float light_mix = 0.62 + stepped * 0.38;
        vec3 lit = mix(base, base * light_mix, lighting_strength * 0.55);

        // Slight color lift so dark stars do not go muddy.
        lit = mix(lit, lit * vec3(1.03, 1.01, 0.98), 0.30);

        // Posterize to keep the pixel-art look.
        lit = floor(clamp(lit, vec3(0.0), vec3(1.0)) * 18.0 + 0.5) / 18.0;

        COLOR = vec4(lit, 1.0);
    }

    if (blackhole_dissolve > 0.001) {
        vec2 dissolve_px = floor(q_uv * pixel_resolution);
        float dissolve_noise = hash31(vec3(dissolve_px * 0.73, seed * 0.017));
        float edge = 1.0 - blackhole_dissolve;
        float threshold = edge + (dissolve_noise - 0.5) * 0.055;
        float removed = step(threshold, q_uv.x);
        COLOR.a *= 1.0 - removed;
    }
}