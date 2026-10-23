// Appearance snapshots inspired by Impasto's ProfileService.
// https://github.com/andreumassanet/impasto — GPL-3.0.
// Only appearance crosses profiles; language, favourites and device state stay put.
.pragma library

var limits = {
    islandGap: [0, 14], bandH: [24, 48], flare: [0, 22], roundMax: [8, 40],
    idleW: [110, 380], hoverDelay: [0, 900], scrimAlpha: [0, 0.7],
    sideMargin: [4, 48], clockSize: [12, 28], motionBlurSamples: [1, 32],
    windowRounding: [0, 20]
};
var switches = ["hoverPreview", "showDate", "showBattery", "reserveSpace", "showArch",
    "showWorkspaces", "showAppName", "showTray", "motionBlur"];
var keys = Object.keys(limits).concat(switches, ["notchStyle", "notchColor", "fontUI"]);

function snapshot(config) {
    var out = {};
    keys.forEach(function (key) { out[key] = config[key]; });
    return out;
}

// The factory values. They are the same as Config.reset(), and they are here
// so that a profile missing something can be FILLED IN, not just rejected.
var pristine = {
    islandGap: 4, bandH: 32, flare: 13, roundMax: 30, idleW: 140,
    hoverDelay: 240, scrimAlpha: 0.0, sideMargin: 16, clockSize: 17,
    motionBlurSamples: 7, windowRounding: 0,
    hoverPreview: true, showDate: false, showBattery: false, reserveSpace: true,
    showArch: true, showWorkspaces: true, showAppName: true, showTray: true,
    motionBlur: true,
    notchStyle: "notch", notchColor: "#000000", fontUI: "Adwaita Sans"
};

// THE CRITERION, ONCE ONLY. Shared by validate() and complete(), which would
// otherwise have been two copies of the same rule bound to drift apart.
function claveValida(key, v) {
    if (limits.hasOwnProperty(key)) {
        if (typeof v !== "number" || !isFinite(v)) return false;
        if (v < limits[key][0] || v > limits[key][1]) return false;
        // Ranges AND integrality: a hand-written bandH of 9999 or 31.5 does not get in.
        if (key !== "scrimAlpha" && Math.floor(v) !== v) return false;
        return true;
    }
    if (switches.indexOf(key) >= 0) return typeof v === "boolean";
    if (key === "notchStyle") return v === "notch" || v === "island";
    // "theme" is the sentinel for "follow the palette" (see Colors.notchTint). A
    // profile saved with the hex already resolved -as used to be done- is still
    // just as valid, so there is nothing to migrate.
    if (key === "notchColor") {
        return typeof v === "string" && (v === "theme" || /^#[0-9a-fA-F]{6}$/.test(v));
    }
    if (key === "fontUI") return typeof v === "string" && !!v.trim() && v.length <= 128;
    return false;
}

function validate(values) {
    if (!values || typeof values !== "object" || Array.isArray(values)) return null;
    var out = {};
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (!claveValida(key, values[key])) return null;
        out[key] = values[key];
    }
    return out;
}

// A PROFILE MISSING A KEY USED TO LIE IN ITS THUMBNAIL.
//
// validate() is all or nothing: the first key that fails returns null. And
// SettingsProfiles.qml paints `card.validValues || Config`, so an invalid
// profile was drawn with YOUR CURRENT LOOK, implying that the profile was
// identical to what you already have, with the Aplicar (Apply) button greyed
// out and no word as to why. The case that matters is the day a new key is
// added: ALL saved profiles would become invalid at a stroke and stop applying.
//
// MISSING AND IMPOSSIBLE ARE NOT THE SAME THING, and the first version of this
// treated them alike. They are told apart:
//
//   · the key IS NOT THERE  -> it is filled in with the factory value. It is the
//     old profile missing something that did not exist yet when it was saved,
//     and filling it in is exactly what was wanted.
//   · the key IS THERE and is IMPOSSIBLE (a bandH of -100) -> the whole profile
//     is REJECTED. That is not an old profile, it is corruption or a hand edit,
//     and silently changing your look to the factory values would be worse
//     than doing nothing. The check in tools/appearance-check.py covers this
//     case ("reject invalid profile without partial changes") and it is right.
//
// The fill-in idea is impasto's SettingsService.complete() (:328-339).
function complete(values) {
    if (!values || typeof values !== "object" || Array.isArray(values)) return null;
    var out = {};
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (values[key] === undefined) out[key] = pristine[key];
        else if (claveValida(key, values[key])) out[key] = values[key];
        else return null;
    }
    return out;
}
