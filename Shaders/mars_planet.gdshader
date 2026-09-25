shader_type canvas_item;
render_mode unshaded;

uniform vec2 rotation_xy = vec2(0.45, -0.08);
uniform float seed : hint_range(0.0, 1000.0) = 41.0;
uniform float pixel_resolution : hint_range(48.0, 256.0, 1.0) = 128.0;
uniform float planet_radius : hint_range(0.55, 0.95) = 0.78;
uniform vec3 light_direction = vec3(-0.65, -0.25, 0.72);

const vec3 DARK_ROCK = vec3(0.19, 0.075, 0.040);
const vec3 BASALT = vec3(0.29, 0.105, 0.055);
const vec3 RUST = vec3(0.55, 0.190, 0.080);
const vec3 DUST = vec3(0.72, 0.310, 0.130);
const vec3 PALE_DUST = vec3(0.82, 0.455, 0.230);
const vec3 ICE = vec3(0.86, 0.82, 0.73);
const vec3 ATMOSPHERE = vec3(0.72, 0.30, 0.12);

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
    return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

float fbm(vec3 p) {
    float v = 0.0;
    float a = 0.55;
    v += noise3(p) * a;
    p = p * 2.03 + vec3(9.1, 4.7, 13.2); a *= 0.5;
    v += noise3(p) * a;
    p = p * 2.07 + vec3(2.4, 17.0, 5.6); a *= 0.5;
    v += noise3(p) * a;
    p = p * 2.01 + vec3(14.2, 1.8, 7.9); a *= 0.5;
    v += noise3(p) * a;
    return v / 1.03125;
}

vec3 rotate_y(vec3 p, float a) {
    float c = cos(a); float s = sin(a);
    return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}
vec3 rotate_x(vec3 p, float a) {
    float c = cos(a); float s = sin(a);
    return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}
vec3 rotate_planet(vec3 p, vec2 rot) {
    return rotate_x(rotate_y(p, rot.x), rot.y);
}

void fragment() {
    vec2 q_uv = (floor(UV * pixel_resolution) + 0.5) / pixel_resolution;
    vec2 p = (q_uv * 2.0 - 1.0) / planet_radius;
    float d = length(p);

    if (d > 1.0) {
        if (d <= 1.035) {
            float ring = 1.0 - smoothstep(1.0, 1.035, d);
            float a = floor(ring * 3.0) / 3.0;
            COLOR = vec4(ATMOSPHERE * (0.32 + ring * 0.45), a * 0.42);
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 normal = normalize(vec3(p.x, p.y, z));
        vec3 pos = rotate_planet(normal, rotation_xy);
        vec3 seed_offset = vec3(seed * 0.061, seed * 0.097, seed * 0.043);

        float broad = fbm(pos * 1.55 + seed_offset);
        float terrain = fbm(pos * 4.4 + seed_offset * 1.7);
        float fine = fbm(pos * 10.5 + seed_offset * 0.63);
        float height = broad * 0.58 + terrain * 0.30 + fine * 0.12;

        vec3 base = mix(RUST, DUST, smoothstep(0.37, 0.68, height));
        base = mix(base, PALE_DUST, smoothstep(0.70, 0.86, height));

        // Dark volcanic provinces / basins.
        float dark_region = smoothstep(0.60, 0.78, fbm(pos * 2.6 + seed_offset + vec3(3.0, 8.0, 1.0)));
        base = mix(base, BASALT, dark_region * 0.58);

        // Canyon/ridge streaks from high-frequency ridged noise.
        float ridge = abs(fbm(pos * 7.8 + seed_offset * 0.4) * 2.0 - 1.0);
        float canyon = 1.0 - smoothstep(0.05, 0.20, ridge);
        base = mix(base, DARK_ROCK, canyon * 0.48);

        // Polar frost, intentionally smaller than Earth's caps.
        float latitude = abs(pos.y);
        float cap_noise = fbm(pos * 6.0 + seed_offset * 0.8);
        float cap_edge = 0.87 - (cap_noise - 0.5) * 0.045;
        float cap = smoothstep(cap_edge, cap_edge + 0.035, latitude);
        base = mix(base, ICE, cap);

        // Very sparse dusty haze.
        float haze = smoothstep(0.72, 0.79, fbm(pos * 5.2 + seed_offset * 1.3 + vec3(15.0, 2.0, 6.0)));
        base = mix(base, PALE_DUST, haze * 0.13);

        vec3 ldir = normalize(light_direction);
        float diffuse = clamp(dot(normal, ldir), 0.0, 1.0);
        float stepped = floor(diffuse * 5.0) / 4.0;
        stepped = clamp(stepped, 0.0, 1.0);
        vec3 lit = base * (0.12 + stepped * 0.88);

        float fresnel = pow(1.0 - z, 3.0);
        lit = mix(lit, ATMOSPHERE, clamp(fresnel * (0.18 + diffuse * 0.45), 0.0, 0.32));
        COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), 1.0);
    }
}
