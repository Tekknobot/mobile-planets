shader_type canvas_item;
render_mode unshaded;

uniform vec2 rotation_xy = vec2(0.45, -0.08);
uniform float seed : hint_range(0.0, 1000.0) = 17.0;
uniform float pixel_resolution : hint_range(48.0, 256.0, 1.0) = 128.0;
uniform float planet_radius : hint_range(0.55, 0.95) = 0.78;
uniform vec3 light_direction = vec3(-0.65, -0.25, 0.72);

const vec3 DEEP_OCEAN = vec3(0.018, 0.075, 0.180);
const vec3 OCEAN = vec3(0.025, 0.180, 0.390);
const vec3 SHALLOW = vec3(0.055, 0.330, 0.500);
const vec3 SAND = vec3(0.705, 0.650, 0.370);
const vec3 GRASS = vec3(0.110, 0.390, 0.185);
const vec3 FOREST = vec3(0.045, 0.235, 0.120);
const vec3 HIGHLAND = vec3(0.315, 0.340, 0.245);
const vec3 ROCK = vec3(0.430, 0.430, 0.395);
const vec3 ICE = vec3(0.790, 0.900, 0.940);
const vec3 SNOW = vec3(0.930, 0.965, 0.965);
const vec3 ATMOSPHERE = vec3(0.080, 0.550, 0.900);

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
    float amp = 0.54;
    value += noise3(p) * amp;
    p = p * 2.03 + vec3(11.7, 4.3, 7.1);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.01 + vec3(3.9, 15.1, 1.8);
    amp *= 0.5;
    value += noise3(p) * amp;
    p = p * 2.07 + vec3(8.2, 2.6, 13.4);
    amp *= 0.5;
    value += noise3(p) * amp;
    return value / 1.0125;
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

vec3 rotate_planet(vec3 p, vec2 rot) {
    p = rotate_y(p, rot.x);
    p = rotate_x(p, rot.y);
    return p;
}

void fragment() {
    // Quantize before all sphere math so the silhouette and shading are truly pixelated.
    vec2 q_uv = (floor(UV * pixel_resolution) + 0.5) / pixel_resolution;
    vec2 p = (q_uv * 2.0 - 1.0) / planet_radius;
    float d = length(p);

    // Atmosphere / empty space outside the planet.
    if (d > 1.0) {
        if (d <= 1.075) {
            float ring = 1.0 - smoothstep(1.0, 1.075, d);
            float a = floor(ring * 4.0) / 4.0;

            COLOR = vec4(
                ATMOSPHERE * (0.38 + ring * 0.62),
                a * 0.82
            );
        } else {
            COLOR = vec4(0.0);
        }
    } else {
        float z = sqrt(max(0.0, 1.0 - dot(p, p)));

        vec3 normal = normalize(
            vec3(p.x, p.y, z)
        );

        vec3 sample_pos = rotate_planet(normal, rotation_xy);

        // Seed offsets the procedural field while preserving spherical continuity.
        vec3 seed_offset = vec3(
            seed * 0.071,
            seed * 0.113,
            seed * 0.047
        );

        // Large continental masses plus smaller breakup/detail.
        float continental =
            fbm(sample_pos * 1.65 + seed_offset);

        float detail =
            fbm(sample_pos * 4.8 + seed_offset * 1.73);

        float ridges =
            abs(
                fbm(
                    sample_pos * 7.4 +
                    seed_offset * 0.61
                ) * 2.0 - 1.0
            );

        float height =
            continental * 0.78 +
            detail * 0.22;

        // Slight equatorial bias keeps large polar continents from dominating.
        float latitude = abs(sample_pos.y);

        height -=
            smoothstep(
                0.72,
                1.0,
                latitude
            ) * 0.035;

        float sea_level = 0.535;

        vec3 base_color;

        // OCEAN
        if (height < sea_level) {
            float depth =
                clamp(
                    (sea_level - height) / 0.22,
                    0.0,
                    1.0
                );

            base_color =
                mix(
                    SHALLOW,
                    OCEAN,
                    smoothstep(
                        0.04,
                        0.55,
                        depth
                    )
                );

            base_color =
                mix(
                    base_color,
                    DEEP_OCEAN,
                    smoothstep(
                        0.55,
                        1.0,
                        depth
                    )
                );
        }

        // LAND
        else {
            float elevation =
                (height - sea_level) / 0.30;

            float moisture =
                fbm(
                    sample_pos * 3.1 +
                    seed_offset * 2.13 +
                    vec3(5.0, 1.0, 9.0)
                );

            if (elevation < 0.055) {
                base_color = SAND;
            }

            else if (elevation < 0.36) {
                base_color =
                    mix(
                        GRASS,
                        FOREST,
                        smoothstep(
                            0.45,
                            0.72,
                            moisture
                        )
                    );
            }

            else if (elevation < 0.63) {
                base_color = HIGHLAND;
            }

            else {
                base_color =
                    mix(
                        ROCK,
                        SNOW,
                        smoothstep(
                            0.68,
                            0.93,
                            elevation +
                            (1.0 - ridges) * 0.14
                        )
                    );
            }
        }

        // Irregular polar ice.
        float ice_noise =
            fbm(
                sample_pos * 5.3 +
                seed_offset * 0.82 +
                vec3(7.0, 19.0, 3.0)
            );

        float ice_edge =
            0.74 -
            (ice_noise - 0.5) * 0.105;

        float ice_amount =
            smoothstep(
                ice_edge,
                ice_edge + 0.055,
                latitude
            );

        base_color =
            mix(
                base_color,
                mix(
                    ICE,
                    SNOW,
                    smoothstep(
                        0.82,
                        0.98,
                        latitude
                    )
                ),
                ice_amount
            );

        // Clouds move slightly faster than the planet surface.
        vec3 cloud_pos = rotate_planet(normal, rotation_xy * vec2(1.08, 1.03) + vec2(0.22, 0.0));

        float clouds =
            fbm(
                cloud_pos * 4.25 +
                seed_offset * 1.31 +
                vec3(21.0, 3.0, 14.0)
            );

        clouds =
            smoothstep(
                0.655,
                0.735,
                clouds
            );

        clouds *=
            1.0 -
            ice_amount * 0.6;

        base_color =
            mix(
                base_color,
                vec3(0.80, 0.86, 0.86),
                clouds * 0.54
            );

        // Four-band stepped lighting.
        vec3 ldir =
            normalize(light_direction);

        float diffuse =
            clamp(
                dot(normal, ldir),
                0.0,
                1.0
            );

        float stepped =
            floor(diffuse * 4.0) / 3.0;

        stepped =
            clamp(
                stepped,
                0.0,
                1.0
            );

        float light =
            0.18 +
            stepped * 0.82;

        vec3 lit =
            base_color * light;

        // Inner atmospheric rim.
        float fresnel =
            pow(
                1.0 - z,
                2.3
            );

        float day_facing =
            0.35 +
            diffuse * 0.65;

        lit =
            mix(
                lit,
                ATMOSPHERE,
                clamp(
                    fresnel *
                    0.78 *
                    day_facing,
                    0.0,
                    0.72
                )
            );

        // Pixel water highlight.
        if (height < sea_level) {
            float spec =
                pow(
                    max(
                        dot(
                            reflect(
                                -ldir,
                                normal
                            ),
                            vec3(0.0, 0.0, 1.0)
                        ),
                        0.0
                    ),
                    22.0
                );

            spec =
                step(0.46, spec) *
                step(0.28, diffuse);

            lit +=
                vec3(
                    0.18,
                    0.24,
                    0.27
                ) * spec;
        }

        COLOR =
            vec4(
                clamp(
                    lit,
                    vec3(0.0),
                    vec3(1.0)
                ),
                1.0
            );
    }
}
