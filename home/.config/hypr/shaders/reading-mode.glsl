#version 320 es

/*
 * Reading mode for Diego's rice.
 *
 * Our own implementation, inspired by surface-dots' e-ink mode:
 * https://github.com/snes19xx/surface-dots
 *
 * The screen is mapped to a palette of warm paper + ink, with a very fine
 * static texture. It is static on purpose: grain that moved every frame would
 * tire the eyes more and force redraws without adding any information.
 */

precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float bayer4(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    const mat4 matrix = mat4(
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0
    );
    return matrix[x][y] / 16.0;
}

void main() {
    vec4 source = texture(tex, v_texcoord);
    vec2 px = gl_FragCoord.xy;

    // Perceptual luminance: keeps legibility better than (r+g+b)/3.
    float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
    gray = pow(clamp(gray, 0.0, 1.0), 1.08);
    gray = smoothstep(0.055, 0.945, gray);

    // Coarse fibre + fine dust, both anchored to the physical pixel.
    float fiber = hash21(floor(px / 9.0));
    float dust = hash21(floor(px / 2.0) + vec2(19.0, 7.0));
    float paperMask = smoothstep(0.28, 0.94, gray);
    gray += ((fiber - 0.5) * 0.020 + (dust - 0.5) * 0.010) * paperMask;

    // A minimal dither avoids banding in gradients without turning text into noise.
    gray += (bayer4(px) - 0.5) * 0.014;
    gray = clamp(gray, 0.0, 1.0);

    vec3 ink = vec3(0.095, 0.090, 0.100);
    vec3 paper = vec3(0.945, 0.925, 0.865);
    vec3 colour = mix(ink, paper, gray);

    // The edge falls off only slightly: it feels like a sheet of paper without darkening the corners.
    float edge = smoothstep(0.44, 0.76, length(v_texcoord - 0.5));
    colour *= 1.0 - edge * 0.035;

    fragColor = vec4(colour, source.a);
}
