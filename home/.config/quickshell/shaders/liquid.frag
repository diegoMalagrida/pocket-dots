// liquid.frag — el indicador de escritorio como un FLUIDO.
//
// No se dibujan figuras y se mueven unas por delante de otras: se resuelve UN
// SOLO campo de distancia con todos los cuerpos dentro, unidos con smin(). Por
// eso dos cuerpos que se acercan se funden con un CUELLO antes de tocarse y al
// separarse el hilo se estira y se rompe. Eso es tension superficial, y es lo
// que el ojo reconoce como liquido.
//
// LAS DOS COSAS QUE HAY QUE HACER BIEN, Y QUE HICE MAL EN LA PRIMERA VERSION:
//
// 1. El antialiasing va con la formula de cobertura, clamp(0.5 - d/fwidth(d)).
//    Da UN pixel de transicion, que es lo que corresponde. Con un
//    smoothstep(-fwidth, +fwidth, d) la transicion abarca DOS pixeles y a este
//    tamano (cuerpos de 8 px) eso no es un borde suave: es un borron.
//
// 2. El color se resuelve con ESA MISMA anchura. Antes lo mezclaba segun la
//    distancia a la pildora en una banda de 4 px, asi que al acercarse al borde
//    el color tiraba hacia el del punto y la pildora salia con un CERCO BLANCO
//    alrededor. Un halo claro pegado al borde es exactamente lo que hace que
//    algo se vea sucio.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// El bloque TIENE que empezar por qt_Matrix + qt_Opacity (lo exige el vertex
// shader por defecto de Qt), y despues solo floats: un vec2 aqui rompe la
// alineacion std140 y el shader lee basura. Los vec4, al final.
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

// Union suave. El termino -kk*hh*(1-hh) es el que fabrica el cuello: donde dos
// superficies casi se tocan, empuja el campo hacia dentro y las cose.
float smin(float a, float b, float kk) {
    float hh = clamp(0.5 + 0.5 * (b - a) / kk, 0.0, 1.0);
    return mix(b, a, hh) - kk * hh * (1.0 - hh);
}

// Cobertura del pixel a partir del campo: 1 dentro, 0 fuera, y exactamente un
// pixel de transicion en el borde, sea cual sea el zoom o la deformacion que
// smin le haya metido al campo.
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

        // El punto senalado se HINCHA en vez de cambiar de color: en un fluido
        // el volumen es la unica respuesta que tiene sentido.
        float r = (abs(float(i) - hoverIdx) < 0.5) ? dotR * 1.45 : dotR;

        // TENSION SUPERFICIAL: el punto se INCLINA hacia la pildora que se
        // acerca, como una gota que nota a otra antes de tocarla. Es lo que
        // convierte el paso de la pildora en algo que le OCURRE a la fila, en
        // vez de algo que ocurre por delante de la fila.
        float near = hasPill > 0.5 ? sdSegment(c, pa, pb, pillR) : 1e6;
        float pull = 1.0 - smoothstep(0.0, k * 2.2, near);
        c.x += sign((pillA + pillB) * 0.5 - c.x) * pull * 2.2;

        // LA PILDORA SE TRAGA EL PUNTO SOBRE EL QUE ESTA. Sin esto, el punto
        // activo queda justo debajo de la pildora, con el mismo centro y el
        // mismo radio: los dos campos EMPATAN, y con un empate no hay formula
        // de color que valga -- salga la que salga, mete el color del punto en
        // el borde de la pildora y aparece un cerco claro. La solucion no es
        // compensarlo al mezclar, es que el empate no exista: un punto que esta
        // dentro de la pildora se ha DISUELTO en ella. Y como se disuelve por
        // profundidad y no por indice, no da un salto al cambiar de escritorio:
        // se lo va tragando segun llega y lo va soltando segun se aleja, que es
        // lo que hace un liquido.
        float swallow = hasPill > 0.5
            ? 1.0 - smoothstep(-dotR, 0.0, sdSegment(c, pa, pb, pillR))
            : 0.0;
        r *= (1.0 - swallow);

        if (r > 0.01) dDots = smin(dDots, sdCircle(p, c, r), k);
    }

    float d = smin(dDots, dPill, k);

    // El color se reparte por COBERTURA de cada cuerpo, no por distancia. Es la
    // diferencia entre "cuanto de este pixel es pildora" (que en el borde libre
    // de la pildora vale 0.5 de pildora y 0 de punto, o sea color de pildora
    // limpio) y "como de cerca esta la pildora" (que en ese mismo borde tiraba
    // hacia el color del punto y pintaba el cerco).
    // Donde no hay ningun cuerpo -- el cuello -- se mezcla por distancia
    // relativa, que ahi si es lo que toca: el cuello es de los dos.
    float cp = coverage(dPill);
    float cd = coverage(dDots);
    float wsum = cp + cd;
    vec4 col = wsum > 0.001
        ? (pillColor * cp + dotColor * cd) / wsum
        : mix(dotColor, pillColor, clamp(0.5 + 0.5 * (dDots - dPill) / max(k, 0.001), 0.0, 1.0));

    // Qt entrega los uniformes de color YA PREMULTIPLICADOS, asi que aqui solo
    // falta escalar por la cobertura. (Volver a multiplicar por col.a los dejaba
    // a un cuarto de intensidad: grises sucios en vez de blancos translucidos.)
    fragColor = col * (coverage(d) * qt_Opacity);
}
