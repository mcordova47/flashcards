// Checks the por / para sentences. See #18.
//
//   node tools/check-por-para.mjs
//
// Holds them to the deck's vocabulary, as check-sentences and
// check-paraphrase hold theirs: every word a deck word, a regular inflection
// of one, or named in the row's Notes. The sentence is there to ask about a
// preposition, and a noun the learner has not met is a second question.
//
// And refuses a contrast that lacks either side, or has only one sentence of
// it. A contrast whose pool is all `por` is a drill that can be passed by
// always typing `por`; and with one sentence of a side, every sighting of
// that side is the same string, which is what the pool is there to prevent.
//
// A sense with no opposite (#43) is held to the half of that which still
// means something: at least two sentences, all answered the way the sense
// takes. One answered the other way is not a second side but a misfiled
// sentence, and is refused as one.

import { loadTable } from "./verb-source.mjs"
import { CSV, ITEMS, PREPOSITIONS, loadRows } from "./por-para-source.mjs"
import { knownWords, unexplained } from "./deck-vocabulary.mjs"

const { verbs, errors: tableErrors } = loadTable()
const { rows, errors } = loadRows()
for (const e of [...tableErrors, ...errors]) console.error(`x ${e}`)
if (tableErrors.length || errors.length) process.exit(1)

const known = knownWords(verbs)
let wrong = 0
for (const r of rows) {
  for (const word of unexplained(known, r.before + r.after, r.notes)) {
    wrong++
    console.error(`x line ${r.line} (${r.text}): ${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }
}

const senses = Object.values(ITEMS).filter(i => i.takes).length
console.log(`${rows.length} sentences over ${Object.keys(ITEMS).length - senses} contrasts and ${senses} one-sided senses:`)
for (const [item, { takes }] of Object.entries(ITEMS)) {
  const counts = Object.keys(PREPOSITIONS).map(p => [p, rows.filter(r => r.item === item && r.answer === p).length])
  console.log(`  ${item.padEnd(20)} ${counts.map(([p, n]) => `${n} ${p}`).join(", ")}${takes ? `  (takes only ${takes})` : ""}`)
  if (!takes) {
    for (const [p, n] of counts.filter(([, n]) => n < 2)) {
      wrong++
      console.error(`x ${item} has ${n} sentence(s) answered ${p}; it needs at least two of each side`)
    }
    continue
  }
  const [, n] = counts.find(([p]) => p === takes)
  if (n < 2) {
    wrong++
    console.error(`x ${item} has ${n} sentence(s) answered ${takes}; it needs at least two`)
  }
  for (const r of rows.filter(r => r.item === item && r.answer !== takes)) {
    wrong++
    console.error(`x line ${r.line} (${r.text}): ${item} takes only ${takes}, so a sentence answered ${r.answer} is in the wrong item`)
  }
}

if (wrong) {
  console.error(`${wrong} problem(s) in ${CSV}`)
  process.exit(1)
}
