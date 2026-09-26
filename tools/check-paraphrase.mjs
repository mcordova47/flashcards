// Proves every paraphrase row says what its targets claim it says.
//
//   node tools/check-paraphrase.mjs
//
// For every row it looks up the stated verb, tense and person in the
// conjugation table and requires that exact form to appear in the model
// answer. The table is the one source of truth for forms: this reads it, and
// does not conjugate anything itself. See #17.
//
// It also holds the corpus to the deck's vocabulary, as check-sentences holds
// the tense-shift bank: every word a deck word, a regular inflection of one,
// or named in the row's Notes. A prompt that teaches a tense should not also
// be teaching three new nouns.
//
// What a row is *allowed to be* - its id, a verb the table has, a coherent
// trap - is tools/paraphrase-source.mjs, so that sync-paraphrase refuses the
// same things before it writes a module.
//
// Exact means exact. Not `Exercise.matches`, which strips accents because
// that is right for grading a phone keyboard - here it would let `leí` pass
// as `lei` and the corpus would ship the error.

import { loadTable } from "./verb-source.mjs"
import { CSV, loadPrompts } from "./paraphrase-source.mjs"
import { knownWords, unexplained, words } from "./deck-vocabulary.mjs"

const { verbs, errors: tableErrors } = loadTable()
if (tableErrors.length) {
  console.error(`x the conjugation table is broken; run check-verbs first`)
  process.exit(1)
}

const { prompts, errors } = loadPrompts(verbs)
for (const e of errors) console.error(`x ${e}`)
if (errors.length) {
  console.error(`${errors.length} problem(s) in ${CSV}`)
  process.exit(1)
}

const table = new Map(verbs.map(v => [v.infinitive, v.cells]))
const known = knownWords(verbs)
const counts = new Map()
let wrong = 0

for (const p of prompts) {
  const fail = message => {
    wrong++
    console.error(`x line ${p.line} (${p.model}): ${message}`)
  }

  const form = table.get(p.verb)?.get(`${p.tense.name}.${p.person.name}`)
  if (form && !words(p.model).includes(form)) {
    fail(`expected ${p.verb} ${p.tense.name} ${p.person.name}, ${form}, to appear`)
  }

  // Outside the deck is allowed, silently is not.
  for (const word of unexplained(known, p.model, p.notes)) {
    fail(`${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }

  const confusion = [p.trap === "verb" ? p.verb : p.tense.name, p.against].sort().join(" / ")
  counts.set(confusion, (counts.get(confusion) ?? 0) + 1)
}

console.log(`${prompts.length} rows, by confusion:`)
for (const [confusion, n] of [...counts].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(3)}  ${confusion}`)

if (wrong) {
  console.error(`${wrong} problem(s) in ${CSV}`)
  process.exit(1)
}
