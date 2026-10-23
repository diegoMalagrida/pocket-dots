// liquid.frag — the workspace indicator as a FLUID.
//
// Shapes are not drawn and moved in front of one another: ONE SINGLE distance
// field is solved with every body inside it, joined with smin(). That is why
// two bodies coming together merge with a NECK before they touch, and as they
// separate the thread stretches and snaps. That is surface tension, and it is
// what the eye recognises as liquid.
//
// THE TWO THINGS THAT HAVE TO BE DONE RIGHT, AND THAT I GOT WRONG IN THE FIRST
// VERSION:
//
// 1. Antialiasing uses the coverage formula, clamp(0.5 - d/fwidth(d)).
//    It gives ONE pixel of transition, which is what it should be. With a
//    smoothstep(-fwidth, +fwidth, d) the transition spans TWO pixels, and at
//    this size (8 px bodies) that is not a soft edge: it is a smudge.
//
// 2. Colour is resolved with THAT SAME width. I used to mix it according to
//    the distance to the pill over a 4 px band, so near the edge the colour
//    pulled towards the dot's and the pill came out with a WHITE RING around
//    it. A light halo hugging the edge is exactly what makes something look
//    dirty.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// The block HAS to start with qt_Matrix + qt_Opacity (Qt's default vertex
// shader demands it), and then only floats: a vec2 here breaks the std140
// alignment and the shader reads garbage. The vec4s go at the end.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float count;
    float stepX;
    float first;
    float dotR;
    float pillA;
    float pillB;
    float pillR;
    float k;
    float w;
    float h;
    float hasPill;
    float hoverIdx;
    vec4 dotColor;
    vec4 pillColor;
};

float sdCircle(vec2 p, vec2 c, float r) { return length(p - c) - r; }

float sdSegment(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * t) - r;
}

// Smooth union. The -kk*hh*(1-hh) term is what builds the neck: where two
// surfaces almost touch, it pushes the field inwards and stitches them.
float smin(float a, float b, float kk) {
    float hh = clamp(0.5 + 0.5 * (b - a) / kk, 0.0, 1.0);
    return mix(b, a, hh) - kk * hh * (1.0 - hh);
}

// Pixel coverage from the field: 1 inside, 0 outside, and exactly one pixel
// of transition at the edge, whatever the zoom or the distortion smin has put
// into the field.
float coverage(float d) { return clamp(0.5 - d / max(fwidth(d), 1e-5), 0.0, 1.0); }

void main() {
    vec2 p = qt_TexCoord0 * vec2(w, h);
    float cy = h * 0.5;

    vec2 pa = vec2(pillA, cy), pb = vec2(pillB, cy);

    float dPill = hasPill > 0.5 ? sdSegment(p, pa, pb, pillR) : 1e6;

    float dDots = 1e6;
    for (int i = 0; i < 16; ++i) {
        if (float(i) >= count) break;
        vec2 c = vec2(first + stepX * float(i), cy);

        // The hovered dot SWELLS instead of changing colour: in a fluid,
        // volume is the only response that makes sense.
        float r = (abs(float(i) - hoverIdx) < 0.5) ? dotR * 1.45 : dotR;

        // SURFACE TENSION: the dot LEANS towards the approaching pill, like a
        // drop that senses another before touching it. It is what turns the
        // pill's passing into something that HAPPENS TO the row, instead of
        // something that happens in front of the row.
        float near = hasPill > 0.5 ? sdSegment(c, pa, pb, pillR) : 1e6;
        float pull = 1.0 - smoothstep(0.0, k * 2.2, near);
        c.x += sign((pillA + pillB) * 0.5 - c.x) * pull * 2.2;

        // THE PILL SWALLOWS THE DOT IT IS SITTING ON. Without this, the active
        // dot sits right under the pill, with the same centre and the same
        // radius: the two fields TIE, and with a tie no colour formula will
        // do -- whichever one you pick, it puts the dot's colour into the
        // pill's edge and a light ring appears. The fix is not to compensate
        // for it when mixing, it is for the tie not to exist: a dot that is
        // inside the pill has DISSOLVED into it. And since it dissolves by
        // depth and not by index, it does not jump when you change workspace:
        // the pill swallows it as it arrives and lets it go as it moves away,
        // which is what a liquid does.
        float swallow = hasPill > 0.5
            ? 1.0 - smoothstep(-dotR, 0.0, sdSegment(c, pa, pb, pillR))
            : 0.0;
        r *= (1.0 - swallow);

        if (r > 0.01) dDots = smin(dDots, sdCircle(p, c, r), k);
    }

    float d = smin(dDots, dPill, k);

    // Colour is shared out by each body's COVERAGE, not by distance. It is the
    // difference between "how much of this pixel is pill" (which at the pill's
    // free edge is 0.5 pill and 0 dot, i.e. clean pill colour) and "how close
    // is the pill" (which at that same edge pulled towards the dot's colour
    // and painted the ring).
    // Where there is no body at all -- the neck -- it mixes by relative
    // distance, which there IS the right thing: the neck belongs to both.
    float cp = coverage(dPill);
    float cd = coverage(dDots);
    float wsum = cp + cd;
    vec4 col = wsum > 0.001
        ? (pillColor * cp + dotColor * cd) / wsum
        : mix(dotColor, pillColor, clamp(0.5 + 0.5 * (dDots - dPill) / max(k, 0.001), 0.0, 1.0));

    // Qt hands over the colour uniforms ALREADY PREMULTIPLIED, so all that is
    // left here is to scale by the coverage. (Multiplying by col.a again left
    // them at a quarter of their intensity: dirty greys instead of translucent
    // whites.)
    fragColor = col * (coverage(d) * qt_Opacity);
}
