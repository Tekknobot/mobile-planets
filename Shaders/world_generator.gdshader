shader_type canvas_item;
render_mode unshaded;

uniform vec2 rotation_xy = vec2(0.0, 0.0);
uniform float seed : hint_range(0.0, 1000000.0) = 17.0;
uniform float pixel_resolution : hint_range(48.0, 256.0, 1.0) = 128.0;
uniform float planet_radius : hint_range(0.55, 0.95) = 0.78;
uniform int body_type = 0; // 0 earthlike, 1 desert, 2 ice, 3 gas giant, 4 lava, 5 moon
uniform vec3 local_light_dir = vec3(-0.65, -0.25, 0.72);
uniform float lighting_strength : hint_range(0.0, 1.0) = 0.92;
uniform bool impact_enabled = false;
uniform vec3 impact_center = vec3(0.0, 0.0, 1.0);
uniform float impact_radius : hint_range(0.04, 0.30) = 0.13;
uniform float climate_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float blackhole_dissolve : hint_range(0.0, 1.0) = 0.0;

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
    float amp = 0.55;
    value += noise3(p) * amp;
    p = p * 2.02 + vec3(11.7, 4.3, 7.1);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.01 + vec3(3.9, 15.1, 1.8);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.06 + vec3(8.2, 2.6, 13.4);
    amp *= 0.5;
    value += noise3(p) * amp;
    return value / 1.03125;
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

vec3 posterize_color(vec3 color, float levels) {
    return floor(clamp(color, vec3(0.0), vec3(1.0)) * levels + 0.5) / levels;
}

vec3 boost_saturation(vec3 color, float amount) {
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(vec3(luma), color, amount);
}

void fragment() {
    vec2 q_uv = (floor(UV * pixel_resolution) + 0.5) / pixel_resolution;
    vec2 p = (q_uv * 2.0 - 1.0) / planet_radius;
    float d = length(p);

    vec3 atmosphere_color = vec3(0.10, 0.42, 0.76);
    float atmosphere_strength = 0.70;
    if (body_type == 1) {
        atmosphere_color = vec3(0.52, 0.34, 0.18);
        atmosphere_strength = 0.34;
    } else if (body_type == 2) {
        atmosphere_color = vec3(0.56, 0.86, 0.95);
        atmosphere_strength = 0.46;
    } else if (body_type == 3) {
        atmosphere_color = vec3(0.82, 0.69, 0.54);
        atmosphere_strength = 0.60;
    } else if (body_type == 4) {
        atmosphere_color = vec3(0.90, 0.24, 0.12);
        atmosphere_strength = 0.18;
    } else if (body_type == 5) {
        atmosphere_color = vec3(0.36, 0.38, 0.42);
        atmosphere_strength = 0.10;
    }

    float heat = max(climate_shift, 0.0);
    float freeze = max(-climate_shift, 0.0);
    atmosphere_color = mix(atmosphere_color, vec3(0.92, 0.38, 0.16), heat * 0.34);
    atmosphere_color = mix(atmosphere_color, vec3(0.55, 0.84, 0.98), freeze * 0.42);
    atmosphere_strength = clamp(atmosphere_strength + freeze * 0.08 - heat * 0.08, 0.08, 0.82);

    if (d > 1.0) {
        if (d <= 1.08) {
            float ring = 1.0 - smoothstep(1.0, 1.08, d);
            float a = floor(ring * 4.0) / 4.0;
            COLOR = vec4(atmosphere_color * (0.42 + ring * 0.58), a * atmosphere_strength);
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));
        vec3 normal = normalize(vec3(p.x, p.y, z));
        vec3 sample_pos = rotate_y(normal, rotation_xy.x);
        sample_pos = rotate_x(sample_pos, rotation_xy.y);
        vec3 seed_offset = vec3(seed * 0.071, seed * 0.113, seed * 0.047);
        float latitude = abs(sample_pos.y);
        vec3 base_color = vec3(0.5);
        float water_mask = 0.0;

        if (body_type == 0) {
            float continental = fbm(sample_pos * 1.65 + seed_offset);
            float detail = fbm(sample_pos * 4.8 + seed_offset * 1.73);
            float ridges = abs(fbm(sample_pos * 7.4 + seed_offset * 0.61) * 2.0 - 1.0);
            float height = continental * 0.78 + detail * 0.22;
            height -= smoothstep(0.72, 1.0, latitude) * 0.035;
            float sea_level = 0.535;

            if (height < sea_level) {
                water_mask = 1.0;
                float depth = clamp((sea_level - height) / 0.22, 0.0, 1.0);
                vec3 shallow = vec3(0.08, 0.36, 0.56);
                vec3 ocean = vec3(0.04, 0.22, 0.42);
                vec3 deep = vec3(0.02, 0.10, 0.23);
                base_color = mix(shallow, ocean, smoothstep(0.04, 0.55, depth));
                base_color = mix(base_color, deep, smoothstep(0.55, 1.0, depth));
            } else {
                float elevation = (height - sea_level) / 0.30;
                float moisture = fbm(sample_pos * 3.1 + seed_offset * 2.13 + vec3(5.0, 1.0, 9.0));
                if (elevation < 0.055) {
                    base_color = vec3(0.72, 0.66, 0.38);
                } else if (elevation < 0.36) {
                    base_color = mix(vec3(0.13, 0.41, 0.20), vec3(0.05, 0.25, 0.13), smoothstep(0.45, 0.72, moisture));
                } else if (elevation < 0.63) {
                    base_color = vec3(0.33, 0.36, 0.25);
                } else {
                    base_color = mix(vec3(0.43, 0.43, 0.40), vec3(0.93, 0.96, 0.96), smoothstep(0.68, 0.93, elevation + (1.0 - ridges) * 0.14));
                }
            }

            float ice_noise = fbm(sample_pos * 5.3 + seed_offset * 0.82 + vec3(7.0, 19.0, 3.0));
            float ice_edge = 0.74 - (ice_noise - 0.5) * 0.105 + heat * 0.38 - freeze * 0.44;
            float ice_amount = smoothstep(ice_edge, ice_edge + 0.055, latitude);
            base_color = mix(base_color, mix(vec3(0.79, 0.90, 0.94), vec3(0.93, 0.96, 0.96), smoothstep(0.82, 0.98, latitude)), ice_amount);

            vec3 cloud_pos = rotate_y(normal, rotation_xy.x * 1.08 + 0.22);
            cloud_pos = rotate_x(cloud_pos, rotation_xy.y * 1.08);
            float clouds = fbm(cloud_pos * 4.25 + seed_offset * 1.31 + vec3(21.0, 3.0, 14.0));
            clouds = smoothstep(0.655, 0.735, clouds) * (1.0 - ice_amount * 0.6);
            base_color = mix(base_color, vec3(0.82, 0.87, 0.88), clouds * (0.52 - heat * 0.20 + freeze * 0.06));

        } else if (body_type == 1) {
            float surface = fbm(sample_pos * 2.2 + seed_offset);
            float dunes = fbm(sample_pos * 8.0 + seed_offset * 0.83);
            float canyons = abs(fbm(sample_pos * 6.4 + vec3(8.0, 2.0, 14.0) + seed_offset) * 2.0 - 1.0);
            base_color = mix(vec3(0.86, 0.60, 0.35), vec3(0.62, 0.30, 0.16), smoothstep(0.32, 0.72, surface));
            base_color = mix(base_color, vec3(0.47, 0.22, 0.12), smoothstep(0.72, 0.95, canyons));
            base_color = mix(base_color, vec3(0.92, 0.79, 0.50), dunes * 0.24);
            float caps = smoothstep(0.86 - (surface - 0.5) * 0.04, 0.97, latitude);
            base_color = mix(base_color, vec3(0.93, 0.94, 0.95), caps * 0.90);

        } else if (body_type == 2) {
            float fields = fbm(sample_pos * 2.0 + seed_offset);
            float crevasses = abs(fbm(sample_pos * 8.8 + seed_offset * 1.4 + vec3(3.0, 14.0, 7.0)) * 2.0 - 1.0);
            base_color = mix(vec3(0.74, 0.92, 0.96), vec3(0.56, 0.80, 0.90), smoothstep(0.38, 0.75, fields));
            base_color = mix(base_color, vec3(0.86, 0.96, 0.99), smoothstep(0.72, 0.95, fields));
            base_color = mix(base_color, vec3(0.25, 0.54, 0.70), smoothstep(0.82, 0.96, crevasses) * 0.48);

        } else if (body_type == 3) {
            float warped_y = sample_pos.y * 7.0 + (fbm(sample_pos * 3.0 + seed_offset) - 0.5) * 1.8;
            float band = 0.5 + 0.5 * sin(warped_y * 5.0 + seed * 0.03);
            float band2 = 0.5 + 0.5 * sin(warped_y * 8.0 + sample_pos.x * 3.0);
            base_color = mix(vec3(0.87, 0.72, 0.54), vec3(0.67, 0.50, 0.37), band);
            base_color = mix(base_color, vec3(0.93, 0.82, 0.66), band2 * 0.28);
            float storm = fbm(vec3(sample_pos.x * 6.0, sample_pos.y * 12.0, sample_pos.z * 6.0) + seed_offset * 2.2);
            float belt = smoothstep(0.58, 0.82, abs(sin(sample_pos.y * 18.0 + seed * 0.02)));
            base_color = mix(base_color, vec3(0.63, 0.44, 0.30), belt * 0.26);
            float red_spot_mask = smoothstep(0.21, 0.0, distance(sample_pos.xy, vec2(0.32, -0.18) + vec2(sin(seed), cos(seed)) * 0.04));
            red_spot_mask *= 0.75 + storm * 0.25;
            base_color = mix(base_color, vec3(0.72, 0.36, 0.23), red_spot_mask);

        } else if (body_type == 4) {
            float crust = fbm(sample_pos * 2.6 + seed_offset);
            float cracks = abs(fbm(sample_pos * 9.6 + seed_offset * 1.7) * 2.0 - 1.0);
            base_color = mix(vec3(0.15, 0.08, 0.07), vec3(0.28, 0.14, 0.09), smoothstep(0.34, 0.72, crust));
            float lava = smoothstep(0.78, 0.96, cracks) * (0.55 + 0.45 * smoothstep(0.25, 0.75, crust));
            base_color = mix(base_color, vec3(1.0, 0.44, 0.08), lava * 0.92);
            float ash = smoothstep(0.72, 0.95, fbm(sample_pos * 6.0 + vec3(9.0, 4.0, 1.0) + seed_offset * 0.8));
            base_color = mix(base_color, vec3(0.40, 0.28, 0.23), ash * 0.22);

        } else {
            float ground = fbm(sample_pos * 2.4 + seed_offset);
            float crater_field = abs(fbm(sample_pos * 8.5 + vec3(7.0, 2.0, 11.0) + seed_offset * 1.3) * 2.0 - 1.0);
            base_color = mix(vec3(0.48, 0.47, 0.45), vec3(0.28, 0.29, 0.31), smoothstep(0.35, 0.80, ground));
            base_color = mix(base_color, vec3(0.61, 0.60, 0.58), smoothstep(0.85, 0.98, crater_field));
            float maria = smoothstep(0.68, 0.90, fbm(sample_pos * 5.5 + seed_offset * 0.6));
            base_color = mix(base_color, vec3(0.22, 0.22, 0.24), maria * 0.45);
        }

        // Smooth climate controls alter the current generated body without changing its seed.
        if (body_type == 0) {
            if (water_mask > 0.5) {
                base_color = mix(base_color, vec3(0.035, 0.13, 0.24), heat * 0.58);
                base_color = mix(base_color, vec3(0.73, 0.90, 0.96), freeze * 0.78);
            } else {
                base_color = mix(base_color, vec3(0.64, 0.32, 0.13), heat * 0.72);
                base_color = mix(base_color, vec3(0.79, 0.89, 0.92), freeze * 0.74);
            }
        } else if (body_type == 1) {
            base_color = mix(base_color, vec3(0.88, 0.28, 0.08), heat * 0.55);
            base_color = mix(base_color, vec3(0.67, 0.79, 0.82), freeze * 0.62);
        } else if (body_type == 2) {
            base_color = mix(base_color, vec3(0.20, 0.43, 0.52), heat * 0.72);
            base_color = mix(base_color, vec3(0.92, 0.98, 1.00), freeze * 0.70);
        } else if (body_type == 3) {
            base_color = mix(base_color, vec3(0.90, 0.36, 0.16), heat * 0.48);
            base_color = mix(base_color, vec3(0.42, 0.68, 0.82), freeze * 0.52);
        } else if (body_type == 4) {
            base_color = mix(base_color, vec3(1.00, 0.28, 0.03), heat * 0.42);
            base_color = mix(base_color, vec3(0.12, 0.15, 0.18), freeze * 0.76);
        } else {
            base_color = mix(base_color, vec3(0.64, 0.38, 0.22), heat * 0.24);
            base_color = mix(base_color, vec3(0.62, 0.70, 0.75), freeze * 0.28);
        }

        // A meteor crater is stored in spherical/sample space, so it remains attached
        // to the generated surface as the player rotates the planet.
        if (impact_enabled && body_type != 3) {
            float crater_d = distance(sample_pos, normalize(impact_center));
            float basin = 1.0 - smoothstep(impact_radius * 0.18, impact_radius, crater_d);
            float core = 1.0 - smoothstep(0.0, impact_radius * 0.48, crater_d);
            float rim = smoothstep(impact_radius * 0.48, impact_radius * 0.70, crater_d) *
                        (1.0 - smoothstep(impact_radius * 0.70, impact_radius, crater_d));
            vec3 crater_dark = mix(base_color * 0.30, vec3(0.045, 0.040, 0.038), 0.48);
            base_color = mix(base_color, crater_dark, basin * 0.78);
            base_color = mix(base_color, vec3(0.025, 0.022, 0.020), core * 0.72);
            base_color += vec3(0.16, 0.14, 0.12) * rim * 0.42;
        }

        // Add a small quantized surface modulation so adjacent terrain pixels stay
        // distinguishable even on generations with similar palette values.
        float micro = fbm(sample_pos * 12.0 + seed_offset * 2.47 + vec3(2.0, 9.0, 4.0));
        float micro_step = floor(micro * 4.0) / 3.0;
        base_color *= mix(0.90, 1.10, micro_step);
        base_color = posterize_color(base_color, 16.0);

        // Sunlight is evaluated in the same rotated sample space as the surface.
        // This makes the stepped light bands rotate coherently with the planet.
        vec3 ldir = normalize(local_light_dir);
        float ndl = dot(sample_pos, ldir);
        float daylight = clamp((ndl + 0.18) / 1.18, 0.0, 1.0);
        float stepped = floor(daylight * 4.999) / 4.0;
        stepped = clamp(stepped, 0.0, 1.0);

        float ambient = 0.34;
        float light_mix = ambient + stepped * (1.0 - ambient);
        float form = 0.90 + pow(z, 0.78) * 0.10;
        vec3 lit = base_color * form;
        lit *= mix(1.0, light_mix, lighting_strength);

        // A restrained warm lift on the sunward bands keeps the terminator clear
        // without washing away the procedural terrain colors.
        float sunward = smoothstep(0.48, 0.92, daylight);
        lit += base_color * sunward * 0.055;

        float fresnel = pow(1.0 - z, 2.45);
        lit = mix(lit, atmosphere_color, clamp(fresnel * atmosphere_strength * 0.82, 0.0, 0.52));

        if (water_mask > 0.5) {
            float spec = pow(max(dot(reflect(-ldir, sample_pos), vec3(0.0, 0.0, 1.0)), 0.0), 18.0);
            spec = step(0.48, spec) * step(0.30, daylight);
            lit += vec3(0.16, 0.21, 0.25) * spec;
        }

        // Final pixel-palette pass: modest contrast + saturation, then posterize.
        lit = boost_saturation(lit, 1.14);
        lit = (lit - vec3(0.5)) * 1.08 + vec3(0.5);
        lit = posterize_color(lit, 18.0);

        COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), 1.0);
    }

    // During the first black-hole phase, remove surface pixels from the side
    // facing the hole. The noise only roughens the advancing edge; the grid
    // stays locked to the same pixel_resolution as the planet artwork.
    if (blackhole_dissolve > 0.001) {
        vec2 dissolve_px = floor(q_uv * pixel_resolution);
        float dissolve_noise = hash31(vec3(dissolve_px * 0.73, seed * 0.017));
        float edge = 1.0 - blackhole_dissolve;
        float threshold = edge + (dissolve_noise - 0.5) * 0.055;
        float removed = step(threshold, q_uv.x);
        COLOR.a *= 1.0 - removed;
    }
}
