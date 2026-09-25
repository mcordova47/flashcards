// Proves every paraphrase row says what its targets claim it says.
//
//   node tools/check-paraphrase.mjs
//
// For every row it looks up the stated verb, tense and person in the
// conjugation table and requires that exact form to appear in the model
// answer. The table is the one source of truth for forms: this reads it, and
// does not conjugate anything itself. See #17.
//
// It also holds the corpus to the deck's vocabulary: every word of every model
// answer must be a deck word, an inflection of one, or named in that row's
// Notes. Inflections are recognised generously - gender, number, and the
// regular conjugations of deck verbs - because this only decides whether a
// word is *known*, never whether it is spelled right. Not generously enough
// for a stem change outside the table: `entiende` is refused although
// `entender` is a deck word, which is why the message says "regular
// inflection" and a Note like "entiende is a stem change; entender is rank
// 275" is an honest way past it.
//
// Exact means exact. Not `Exercise.matches`, which strips accents because
// that is right for grading a phone keyboard - here it would let `leí` pass
// as `lei` and the corpus would ship the error.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { TENSES, PERSONS, ENDINGS, loadTable, regular } from "./verb-source.mjs"

const CSV = "data/es-paraphrase.csv"
const DECK = "data/es-1000.csv"
const HEADER = ["Prompt", "Model", "Verb", "Tense", "Person", "Trap", "Against", "Notes"]
const TRAPS = ["verb", "tense"]

const { verbs, errors: tableErrors } = loadTable()
if (tableErrors.length) {
  console.error(`x the conjugation table is broken; run check-verbs first`)
  process.exit(1)
}

const table = new Map(verbs.map(v => [v.infinitive, v.cells]))
const tenses = TENSES.map(t => t.name), persons = PERSONS.map(p => p.name)
const words = sentence => sentence.toLowerCase().split(/[^a-zñáéíóúü]+/).filter(Boolean)

// Every word the deck teaches, split out of entries like `el / la`,
// `ir(se)` and `llamar(se)`, plus every form in the conjugation table and
// every regular form of every deck verb.
const known = new Set(verbs.flatMap(v => [...v.cells.values()]))
for (const [, , spanish] of parseCsv(fs.readFileSync(DECK, "utf-8")).slice(1)) {
  for (const word of words((spanish ?? "").replace(/\(se\)/g, ""))) {
    known.add(word)
    if (!ENDINGS[word.slice(-2).replace("í", "i")]) continue
    for (const tense of tenses) for (const person of persons) known.add(regular(word, tense, person))
  }
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

const errors = []
const counts = new Map()
const [header, ...body] = parseCsv(fs.readFileSync(CSV, "utf-8"))
if (HEADER.some((c, i) => header[i] !== c) || header.length !== HEADER.length) {
  console.error(`x expected the header ${HEADER.join(",")}, got ${header.join(",")}`)
  process.exit(1)
}

body.forEach((cells, i) => {
  const line = i + 2
  if (cells.length !== HEADER.length) {
    errors.push(`line ${line} has ${cells.length} fields, not ${HEADER.length}`)
    return
  }
  const [prompt, model, verb, tense, person, trap, against, notes] = cells
  const fail = message => errors.push(`line ${line} (${model}): ${message}`)

  if (!prompt || !model) fail("a row needs both a prompt and a model answer")
  if (!table.has(verb)) fail(`${verb} is not one of the ${table.size} verbs in the table`)
  if (!tenses.includes(tense)) fail(`unknown tense ${JSON.stringify(tense)}`)
  if (!persons.includes(person)) fail(`unknown person ${JSON.stringify(person)}`)

  // One trap, and the other targets not also decisions. A verb trap sits in
  // the present, or the learner is choosing a tense as well and the rubric
  // cannot say which mistake they made.
  if (trap === "verb") {
    if (!table.has(against) || against === verb) fail(`against a verb trap, ${JSON.stringify(against)} should be another verb in the table`)
    if (tense !== "present") fail(`a verb trap should sit in the present, not the ${tense}`)
  } else if (trap === "tense") {
    if (!tenses.includes(against) || against === tense) fail(`against a tense trap, ${JSON.stringify(against)} should be another tense`)
  } else {
    fail(`trap should be one of ${TRAPS.join(", ")}, not ${JSON.stringify(trap)}`)
  }

  const form = table.get(verb)?.get(`${tense}.${person}`)
  if (form && !words(model).includes(form)) fail(`expected ${verb} ${tense} ${person}, ${form}, to appear`)

  // Outside the deck is allowed, silently is not.
  for (const word of words(model)) {
    const candidates = lemmas(word)
    if (candidates.some(w => known.has(w))) continue
    if (!candidates.some(w => words(notes).includes(w))) fail(`${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }

  const confusion = [trap === "verb" ? verb : tense, against].sort().join(" / ")
  counts.set(confusion, (counts.get(confusion) ?? 0) + 1)
})

for (const e of errors) console.error(`x ${e}`)

console.log(`${body.length} rows, by confusion:`)
for (const [confusion, n] of [...counts].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(3)}  ${confusion}`)

if (errors.length) {
  console.error(`${errors.length} problem(s) in ${CSV}`)
  process.exit(1)
}
