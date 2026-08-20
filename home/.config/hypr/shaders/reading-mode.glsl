#version 320 es

/*
 * Modo lectura del rice de Diego.
 *
 * Implementacion propia inspirada en el modo e-ink de surface-dots:
 * https://github.com/snes19xx/surface-dots
 *
 * La pantalla se lleva a una paleta de papel calido + tinta, con una textura
 * estatica muy fina. Es estatica a proposito: un grano que se moviese en cada
 * frame cansaria mas la vista y forzaria redibujos sin aportar informacion.
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

    // Luminancia perceptual: conserva mejor la legibilidad que (r+g+b)/3.
    float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
    gray = pow(clamp(gray, 0.0, 1.0), 1.08);
    gray = smoothstep(0.055, 0.945, gray);

    // Fibra gruesa + polvo fino, ambos anclados al pixel fisico.
    float fiber = hash21(floor(px / 9.0));
    float dust = hash21(floor(px / 2.0) + vec2(19.0, 7.0));
    float paperMask = smoothstep(0.28, 0.94, gray);
    gray += ((fiber - 0.5) * 0.020 + (dust - 0.5) * 0.010) * paperMask;

    // Un dither minimo evita bandas en degradados sin convertir texto en ruido.
    gray += (bayer4(px) - 0.5) * 0.014;
    gray = clamp(gray, 0.0, 1.0);

    vec3 ink = vec3(0.095, 0.090, 0.100);
    vec3 paper = vec3(0.945, 0.925, 0.865);
    vec3 colour = mix(ink, paper, gray);

    // El borde cae apenas: da sensacion de hoja sin oscurecer las esquinas.
    float edge = smoothstep(0.44, 0.76, length(v_texcoord - 0.5));
    colour *= 1.0 - edge * 0.035;

    fragColor = vec4(colour, source.a);
}
