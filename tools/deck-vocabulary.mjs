// What counts as a word the deck teaches, for the corpora of Spanish sentences
// that are supposed to be built from them. Shared by tools/check-paraphrase.mjs
// and tools/check-sentences.mjs, so the two banks are held to the same rule.
//
// Inflections are recognised generously - gender, number, and the regular
// conjugations of deck verbs - because this only decides whether a word is
// *known*, never whether it is spelled right. Not generously enough for a stem
// change outside the table: `entiende` is refused although `entender` is a
// deck word, and a Note naming it is the honest way past.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { TENSES, PERSONS, ENDINGS, regular } from "./verb-source.mjs"

const DECK = "data/es-1000.csv"

export const words = sentence => sentence.toLowerCase().split(/[^a-zñáéíóúü]+/).filter(Boolean)

// Every word the deck teaches, split out of entries like `el / la`, `ir(se)`
// and `llamar(se)`, plus every form in the conjugation table and every
// regular form of every deck verb. `verbs` is `loadTable().verbs`.
export const knownWords = verbs => {
  const tenses = TENSES.map(t => t.name), persons = PERSONS.map(p => p.name)
  const known = new Set(verbs.flatMap(v => [...v.cells.values()]))
  for (const [, , spanish] of parseCsv(fs.readFileSync(DECK, "utf-8")).slice(1)) {
    for (const word of words((spanish ?? "").replace(/\(se\)/g, ""))) {
      known.add(word)
      if (!ENDINGS[word.slice(-2).replace("í", "i")]) continue
      for (const tense of tenses) for (const person of persons) known.add(regular(word, tense, person))
    }
  }
  return known
}

// What a word might be an inflection of: `hermanas` of `hermano`, `esta` of
// `este`, `al` of `a`. Returns every candidate, so the caller can accept a
// Note that names any of them.
const CONTRACTIONS = { al: "a", del: "de" }
const lemmas = word => {
  const bare = [word, word.replace(/es$/, ""), word.replace(/s$/, "")]
  return [...new Set([
    ...bare,
    ...bare.filter(w => w.endsWith("a")).flatMap(w => [w.slice(0, -1) + "o", w.slice(0, -1) + "e"]),
    ...(CONTRACTIONS[word] ? [CONTRACTIONS[word]] : []),
  ])]
}

// The words of `sentence` that are neither known nor named in `notes`.
// Outside the deck is allowed; silently is not.
export const unexplained = (known, sentence, notes) =>
  words(sentence).filter(word => {
    const candidates = lemmas(word)
    return !candidates.some(w => known.has(w)) && !candidates.some(w => words(notes).includes(w))
  })
