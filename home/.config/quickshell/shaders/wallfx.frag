// wallfx.frag — the wallpaper transitions (WallpaperFx.qml).
//
// Nothing here knows WHEN a pixel changes: the maps made by ~/.local/bin/wallfx
// say so, and this only reads them. `t` runs from 0 to 1 in time.
//
// Two transitions, one language: crisp 4 px cells eating through the old
// wallpaper along ragged, organic fronts.
//
//   CONTAGION (mode 0), any wallpaper: a handful of colonies land at random
//   places and moments. Each cell that has just flipped burns for an instant
//   in the new palette's most vivid colour, a thin glow rides the front, and
//   now and then a spark jumps ahead of it.
//
//   OUTLINE (mode 1), a wallpaper with a character, nonchalant: the stage steps
//   back a little, a thin quiet line in the palette's light tone draws the
//   character's outline (two pens from the top), the character fills in from
//   that outline, and then the rest of the world spreads out of it. No glow,
//   no flash: it should look effortless. (An earlier version lit it up like a
//   Pokémon evolution; Diego asked for it "more nonchalant, less neon".)
//
// Every extra effect is scaled by sin(πt), so it is exactly zero at both ends,
// and both cameras end where awww draws: the hand-over cannot show.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// qt_Matrix + qt_Opacity first (Qt's vertex shader demands it), then floats
// only, then the vec4s: a vec2 among the floats breaks the std140 layout.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;          // 0..1, linear in time
    float mode;       // 0 contagion, 1 outline
    float sw;         // screen, px
    float sh;
    float fw;         // fieldTex, texels
    float fh;
    float lw;         // lineTex, texels
    float lh;
    float glow;       // 0..1, strength of the contagion's light
    float lineW;      // outline width, px
    float sdRange;    // fieldTex B spans +-sdRange map px
    float seed;       // a different one every change: the sparks never repeat
    vec4 cropOld;     // image uv = xy + screen uv * zw  (awww's "crop": cover, centred)
    vec4 cropNew;
    vec4 ember;       // the new palette's most vivid colour: the contagion's burning edge
    vec4 ink;         // its lightest tone: the outline's line
};
layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;
layout(binding = 3) uniform sampler2D fieldTex;
layout(binding = 4) uniform sampler2D lineTex;

const float PI = 3.14159265;
const float CELL = 4.0;   // px, the size of the pixels that eat through

// ESCENA's curve (motion-language.md): the phases reveal AREA, and an area at a
// steady rate already brakes by itself, so the curve only softens the ends.
float escena(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec2 cam(vec2 uv, float z) { return 0.5 + (uv - 0.5) / z; }
vec3 oldAt(vec2 uv) { return texture(oldTex, cropOld.xy + uv * cropOld.zw).rgb; }
vec2 newUv(vec2 uv, float z) { return cropNew.xy + cam(uv, z) * cropNew.zw; }

// 16-bit surface in lineTex's G (high) and B (low), interpolated by hand: the
// sampler's bilinear filter would blend the two bytes separately.
float s16(vec2 texel) {
    texel = clamp(texel, vec2(0.0), vec2(lw, lh) - 1.0);
    vec4 f = texture(lineTex, (texel + 0.5) / vec2(lw, lh));
    return (floor(f.g * 255.0 + 0.5) * 256.0 + floor(f.b * 255.0 + 0.5)) / 65535.0;
}
float surface(vec2 tuv) {
    vec2 p = tuv * vec2(lw, lh) - 0.5;
    vec2 i = floor(p), f = p - i;
    return mix(mix(s16(i), s16(i + vec2(1.0, 0.0)), f.x),
               mix(s16(i + vec2(0.0, 1.0)), s16(i + vec2(1.0, 1.0)), f.x), f.y);
}

// ───────────────────────────── contagion ─────────────────────────────
//
// fieldTex: each cell's moment (R high, G low), 480x270; lineTex: the same
// moment, blurred, for the glow. No water, no stages: the edge IS the effect,
// and it is the new image's own colours that eat the old one.

float arrivalAt(vec2 c) {
    c = clamp(c, vec2(0.0), vec2(fw, fh) - 1.0);
    vec4 f = texture(fieldTex, (c + 0.5) / vec2(fw, fh));
    return (floor(f.r * 255.0 + 0.5) * 256.0 + floor(f.g * 255.0 + 0.5)) / 65535.0;
}

vec3 contagion(vec2 uv) {
    const float LIFE = 0.05;                // how long a flipped cell burns, in area
    float energy = sin(PI * t);
    float T = escena(t) * (1.0 + LIFE + 0.01) - 0.01;
    float s = surface(uv);
    vec2 cell = floor(uv * vec2(fw, fh));
    float a = arrivalAt(cell);
    float flick = hash(cell);
    vec3 hot = mix(ember.rgb, vec3(1.0), 0.18);
    vec3 c;
    if (a > T) {
        c = oldAt(uv);
        // a spark: a lone cell just ahead of the front lights up for a moment
        float ahead = a - T;
        if (flick > 0.985 && ahead < 0.02)
            c = mix(c, hot, (1.0 - ahead / 0.02) * 0.8 * glow * step(0.0, T));
    } else {
        c = texture(newTex, newUv(uv, 1.0 + 0.025 * (1.0 - escena(t)))).rgb;   // settles from a touch closer
        bool edge = max(max(arrivalAt(cell + vec2(1.0, 0.0)), arrivalAt(cell - vec2(1.0, 0.0))),
                        max(arrivalAt(cell + vec2(0.0, 1.0)), arrivalAt(cell - vec2(0.0, 1.0)))) > T;
        float life = clamp((T - a) / LIFE, 0.0, 1.0);
        float burn = (1.0 - life) * (1.0 - life) * (edge ? 1.0 : 0.55);
        c = mix(c, hot, burn * (0.55 + 0.45 * flick) * 0.85 * glow);
    }
    // the thin glow riding the front, on both sides
    return c + ember.rgb * 0.22 * glow * energy * exp(-abs(s - T) / 0.006);
}

// ───────────────────────────── outline ─────────────────────────────
//
// The maps live in the NEW image's space: fieldTex G = depth inside the
// character (0 on its outline), B = signed distance near it; lineTex R = where
// along the outline each point is, G/B = the order in which the outside
// arrives (outwards from the character, roughened with noise), smooth.

vec3 outline(vec2 uv) {
    // Two cameras, barely: the character settles from a touch closer than its
    // background, which is enough to give it a little depth.
    float zCh = 1.0 + 0.03 * (1.0 - escena(t));
    float zBg = 1.0 + 0.015 * (1.0 - escena(t));
    vec4 f = texture(fieldTex, newUv(uv, zCh));
    float sdPx = (f.b * 2.0 - 1.0) * sdRange * sw * zCh / (fw * cropNew.z);
    float inside = clamp(0.5 - sdPx / max(fwidth(sdPx), 1e-3), 0.0, 1.0);

    // The stage steps back, a little: a fifth darker, a quarter greyer.
    float back = escena(t / 0.18);
    vec3 st = oldAt(uv);
    st = mix(st, vec3(luma(st)), 0.25 * back) * (1.0 - 0.2 * back);

    // The same 4 px cells as the contagion. Each decides by its centre, so the
    // fronts are crisp and stepped; the silhouette itself stays smooth.
    vec2 grid = vec2(sw, sh) / CELL;
    vec2 cuv = (floor(uv * grid) + 0.5) / grid;

    // The character fills in from its outline...
    float Ti = escena((t - 0.32) / 0.32) * 1.02 - 0.01;   // once the line is (almost) drawn
    vec3 cIn = texture(fieldTex, newUv(cuv, zCh)).g <= Ti ? texture(newTex, newUv(uv, zCh)).rgb : st;
    // ...and then the world spreads out of it.
    float To = escena((t - 0.45) / 0.50) * 1.02 - 0.01;
    vec3 cOut = surface(newUv(cuv, zBg)) <= To ? texture(newTex, newUv(uv, zBg)).rgb : st;
    vec3 c = mix(cOut, cIn, inside);

    // The line: thin and quiet, in the palette's lightest tone, drawn by two
    // pens from the top of every contour; it leaves once the character is in.
    float drawP = escena((t - 0.02) / 0.33);
    float lp = texture(lineTex, newUv(uv, zCh)).r;
    float fade = 1.0 - escena((t - 0.45) / 0.25);
    if (lp > 0.0 && lp <= drawP && fade > 0.0) {
        float d = abs(sdPx) - lineW * 0.5;
        float core = clamp(0.5 - d / max(fwidth(sdPx), 1e-3), 0.0, 1.0);
        c = mix(c, ink.rgb, core * 0.75 * fade);
    }
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 c = mode < 0.5 ? contagion(uv) : outline(uv);
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
