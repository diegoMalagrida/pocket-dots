// I18n.qml — la capa de idioma del shell.
//
// EL CASTELLANO ES EL CÓDIGO. Las cadenas siguen escritas en español dentro de
// cada .qml, envueltas en I18n.tr(...). En español tr() devuelve su argumento
// tal cual: no hay diccionario que mantener, ni claves que inventar, ni forma
// de que un texto se quede sin traducir y salga en blanco. Solo el inglés vive
// en un diccionario (translations-en.js), y lo que le falte cae en español, que
// es un fallo visible pero inofensivo.
//
// POR QUÉ NO qsTr() Y .qm: el flujo de Qt Linguist obliga a compilar los .ts y
// a reiniciar la aplicación para cambiar de idioma. Aquí el idioma se cambia
// desde Ajustes y la interfaz entera se repinta en el sitio, porque `lang` es
// una propiedad y todas las asignaciones `text: I18n.tr(...)` son bindings que
// dependen de ella.
pragma Singleton

import Quickshell
import QtQuick
// El diccionario va en un .js importado, no en otro singleton QML: probado que
// un `readonly property var` con las 402 entradas dentro llega como `undefined`
// al leerlo desde aqui. El porque, entero, en la cabecera de translations-en.js.
import "translations-en.js" as Dict

Singleton {
    id: root

    readonly property string lang: Config.language
    readonly property bool english: lang === "en"

    // El rótulo va en su propio idioma a propósito: quien tenga el shell en un
    // idioma que no entiende tiene que poder encontrar el suyo en la lista.
    readonly property var languages: [
        { code: "es", label: "Español" },
        { code: "en", label: "English" }
    ]

    function labelFor(code) {
        for (var i = 0; i < root.languages.length; i++)
            if (root.languages[i].code === code) return root.languages[i].label;
        return code;
    }

    function codeFor(label) {
        for (var i = 0; i < root.languages.length; i++)
            if (root.languages[i].label === label) return root.languages[i].code;
        return "es";
    }

    readonly property var labels: root.languages.map(function (l) { return l.label; })

    // tr("Apagar")                       -> "Shut down"
    // tr("Quedan {0} minutos", 5)        -> "5 minutes left"
    //
    // Los huecos son {0}, {1}, {2} y NO se concatenan fuera: una frase partida
    // en trozos ("Quedan " + n + " minutos") no se puede traducir, porque en
    // otro idioma las piezas van en otro orden.
    function tr(s, a0, a1, a2) {
        var out = root.english && Dict.en[s] !== undefined ? Dict.en[s] : s;
        if (a0 !== undefined) out = out.split("{0}").join(a0);
        if (a1 !== undefined) out = out.split("{1}").join(a1);
        if (a2 !== undefined) out = out.split("{2}").join(a2);
        return out;
    }
}
