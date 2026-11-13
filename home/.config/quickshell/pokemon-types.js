// pokemon-types.js — the pokémon type names, by PokeAPI id, in the languages
// that need a table of their own. Spanish already comes in the team's JSON
// (each type's `es`) and English is the id itself, capitalised; see
// ShellState.pokeTipo().
//
// They cannot go in translations-*.js: those are keyed by the Spanish text,
// and the Spanish type names clash with the badges' ("Roca" is the Rock type
// AND the Boulder Badge, which in Italian are Roccia and Sasso). Same reason
// as the dictionaries for being a .js and not a property of I18n.qml.
//
// The Italian names are the same ones poke-types writes into tipos.json for
// the Super+O pokédex; if one changes, change the other.
.pragma library

var names = {
    it: {
        normal: "Normale", fighting: "Lotta", flying: "Volante",
        poison: "Veleno", ground: "Terra", rock: "Roccia", bug: "Coleottero",
        ghost: "Spettro", steel: "Acciaio", fire: "Fuoco", water: "Acqua",
        grass: "Erba", electric: "Elettro", psychic: "Psico",
        ice: "Ghiaccio", dragon: "Drago", dark: "Buio", fairy: "Folletto"
    },
    pt: {
        normal: "Normal", fighting: "Lutador", flying: "Voador",
        poison: "Venenoso", ground: "Terrestre", rock: "Pedra", bug: "Inseto",
        ghost: "Fantasma", steel: "Aço", fire: "Fogo", water: "Água",
        grass: "Planta", electric: "Elétrico", psychic: "Psíquico",
        ice: "Gelo", dragon: "Dragão", dark: "Sombrio", fairy: "Fada"
    }
};
