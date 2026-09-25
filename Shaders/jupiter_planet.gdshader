shader_type canvas_item;
render_mode unshaded;

uniform vec2 rotation_xy = vec2(0.45, -0.08);
uniform float seed : hint_range(0.0, 1000.0) = 73.0;
uniform float pixel_resolution : hint_range(48.0, 256.0, 1.0) = 128.0;
uniform float planet_radius : hint_range(0.55, 0.95) = 0.78;
uniform vec3 light_direction = vec3(-0.65, -0.25, 0.72);

const vec3 CREAM = vec3(0.85, 0.72, 0.52);
const vec3 PALE = vec3(0.92, 0.84, 0.66);
const vec3 TAN = vec3(0.64, 0.42, 0.25);
const vec3 BROWN = vec3(0.39, 0.22, 0.14);
const vec3 RED_SPOT = vec3(0.67, 0.25, 0.14);
const vec3 RED_LIGHT = vec3(0.82, 0.42, 0.25);
const vec3 ATMOSPHERE = vec3(0.74, 0.60, 0.42);

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0,0.0,0.0));
    float n010 = hash31(i + vec3(0.0,1.0,0.0));
    float n110 = hash31(i + vec3(1.0,1.0,0.0));
    float n001 = hash31(i + vec3(0.0,0.0,1.0));
    float n101 = hash31(i + vec3(1.0,0.0,1.0));
    float n011 = hash31(i + vec3(0.0,1.0,1.0));
    float n111 = hash31(i + vec3(1.0,1.0,1.0));
    float x00 = mix(n000,n100,f.x); float x10 = mix(n010,n110,f.x);
    float x01 = mix(n001,n101,f.x); float x11 = mix(n011,n111,f.x);
    return mix(mix(x00,x10,f.y), mix(x01,x11,f.y), f.z);
}

float fbm(vec3 p) {
    float v = 0.0; float a = 0.56;
    v += noise3(p) * a;
    p = p * 2.02 + vec3(5.1, 13.2, 2.7); a *= 0.5;
    v += noise3(p) * a;
    p = p * 2.08 + vec3(11.0, 3.4, 17.0); a *= 0.5;
    v += noise3(p) * a;
    p = p * 2.01 + vec3(1.8, 8.6, 6.3); a *= 0.5;
    v += noise3(p) * a;
    return v / 1.05;
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
        if (d <= 1.045) {
            float ring = 1.0 - smoothstep(1.0, 1.045, d);
            float a = floor(ring * 4.0) / 4.0;
            COLOR = vec4(ATMOSPHERE * (0.28 + ring * 0.42), a * 0.45);
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 normal = normalize(vec3(p.x, p.y, z));
        vec3 pos = rotate_planet(normal, rotation_xy);
        vec3 seed_offset = vec3(seed * 0.037, seed * 0.071, seed * 0.053);

        // Longitude angle lets the bands meander as the world spins.
        float lon = atan(pos.z, pos.x);
        float lat = pos.y;
        float turbulence = fbm(vec3(lon * 0.42, lat * 7.5, seed * 0.03) + seed_offset * 0.1);
        float warped_lat = lat + (turbulence - 0.5) * 0.075;

        float bands = sin(warped_lat * 36.0 + turbulence * 3.0);
        float fine_bands = sin(warped_lat * 75.0 + fbm(pos * vec3(1.6, 11.0, 1.6) + seed_offset) * 4.0);
        float b = bands * 0.65 + fine_bands * 0.35;

        vec3 base = mix(CREAM, TAN, smoothstep(-0.15, 0.45, b));
        base = mix(base, PALE, smoothstep(0.62, 0.94, -b));
        float dark_belt = smoothstep(0.64, 0.92, b);
        base = mix(base, BROWN, dark_belt * 0.42);

        // Great Red Spot-like storm, located in the southern hemisphere.
        // atan gives a seam-safe longitude; wrap distance to the spot center.
        float target_lon = -0.72;
        float lon_delta = abs(mod(lon - target_lon + 3.14159265, 6.2831853) - 3.14159265);
        vec2 spot_uv = vec2(lon_delta / 0.58, (lat + 0.29) / 0.115);
        float spot_dist = length(spot_uv);
        float spot = 1.0 - smoothstep(0.72, 1.0, spot_dist);
        float spot_core = 1.0 - smoothstep(0.25, 0.72, spot_dist);
        float spot_noise = fbm(pos * 11.0 + seed_offset * 0.7);
        spot *= 0.78 + spot_noise * 0.22;
        base = mix(base, RED_LIGHT, spot);
        base = mix(base, RED_SPOT, spot_core * 0.70);

        vec3 ldir = normalize(light_direction);
        float diffuse = clamp(dot(normal, ldir), 0.0, 1.0);
        float stepped = floor(diffuse * 5.0) / 4.0;
        stepped = clamp(stepped, 0.0, 1.0);
        vec3 lit = base * (0.14 + stepped * 0.86);

        float fresnel = pow(1.0 - z, 2.0);
        lit = mix(lit, ATMOSPHERE, clamp(fresnel * (0.30 + diffuse * 0.52), 0.0, 0.48));
        COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), 1.0);
    }
}
