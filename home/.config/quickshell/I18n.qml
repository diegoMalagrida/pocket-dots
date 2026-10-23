// I18n.qml — the shell's language layer.
//
// SPANISH IS THE CODE. The strings are still written in Spanish inside each
// .qml, wrapped in I18n.tr(...). In Spanish tr() returns its argument as is:
// there is no dictionary to maintain, no keys to invent, and no way for a text
// to go untranslated and come out blank. Only English lives in a dictionary
// (translations-en.js), and whatever it lacks falls back to Spanish, which is
// a visible but harmless failure.
//
// WHY NOT qsTr() AND .qm: the Qt Linguist workflow forces you to compile the
// .ts files and restart the application to change language. Here the language
// is changed from Settings and the whole interface repaints in place, because
// `lang` is a property and every `text: I18n.tr(...)` assignment is a binding
// that depends on it.
pragma Singleton

import Quickshell
import QtQuick
// The dictionary lives in an imported .js, not in another QML singleton: it was
// tested that a `readonly property var` holding the 402 entries arrives as
// `undefined` when read from here. The full reason is in the header of
// translations-en.js.
import "translations-en.js" as Dict

Singleton {
    id: root

    readonly property string lang: Config.language
    readonly property bool english: lang === "en"

    // Each label is in its own language on purpose: someone with the shell in a
    // language they do not understand has to be able to find theirs in the list.
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
    // The placeholders are {0}, {1}, {2} and are NOT concatenated outside: a
    // sentence split into pieces ("Quedan " + n + " minutos") cannot be
    // translated, because in another language the pieces go in another order.
    function tr(s, a0, a1, a2) {
        var out = root.english && Dict.en[s] !== undefined ? Dict.en[s] : s;
        if (a0 !== undefined) out = out.split("{0}").join(a0);
        if (a1 !== undefined) out = out.split("{1}").join(a1);
        if (a2 !== undefined) out = out.split("{2}").join(a2);
        return out;
    }
}
