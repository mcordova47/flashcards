// Checks the trigger frames. See #230.
//
//   node tools/check-triggers.mjs
//
// Holds the words before the gap to the deck's vocabulary, as check-sentences
// and check-por-para hold theirs: every word a deck word, a regular inflection
// of one, or named in the row's Notes. A trigger is there to ask about a mood,
// and a word the learner has not met is a second question.
//
// And holds the bank to the shape that makes it teach a pattern and not a list
// of phrases: every kind of meaning has at least three triggers, so that a kind
// is not learned as one phrase; indicative triggers are at least a quarter of
// the bank, so that always typing the subjunctive loses; and every trigger that
// is the negation of another is marked as a minimal pair with it.
//
// Whether a trigger really takes one mood only, and reads as Mexican Spanish,
// no tool can say. That is the reviewer's, and the native-speaker list (#132).

import { PERSONS, loadTable } from "./verb-source.mjs"
import { CSV, GROUPS, MIN_INDICATIVE_SHARE, MIN_PER_GROUP, loadRows } from "./trigger-source.mjs"
import { knownWords, unexplained } from "./deck-vocabulary.mjs"

const { verbs, errors: tableErrors } = loadTable()
const { rows, errors } = loadRows()
for (const e of [...tableErrors, ...errors]) console.error(`x ${e}`)
if (tableErrors.length || errors.length) process.exit(1)

const known = knownWords(verbs)
let wrong = 0
for (const r of rows) {
  for (const word of unexplained(known, r.trigger, r.notes)) {
    wrong++
    console.error(`x line ${r.line} (${r.trigger}): ${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }
}

console.log(`${rows.length} triggers in ${Object.keys(GROUPS).length} groups:`)
for (const [group, { mood, label }] of Object.entries(GROUPS)) {
  const n = rows.filter(r => r.group === group).length
  console.log(`  ${group.padEnd(14)} ${String(n).padStart(2)}  ${mood.padEnd(12)} ${label}`)
  if (n < MIN_PER_GROUP) {
    wrong++
    console.error(`x ${group} has ${n} trigger(s); a kind of meaning needs at least ${MIN_PER_GROUP}, or it is learned as a phrase`)
  }
}

const indicative = rows.filter(r => r.mood === "indicative").length
const share = indicative / rows.length
console.log(`  indicative: ${indicative} of ${rows.length} (${Math.round(share * 100)}%)`)
if (share < MIN_INDICATIVE_SHARE) {
  wrong++
  console.error(`x ${indicative} of ${rows.length} triggers are indicative; at least ${MIN_INDICATIVE_SHARE * 100}% are needed, or typing the subjunctive always wins`)
}

// A trigger that is another with `no` put in is a minimal pair, and the only
// kind worth having: say so, or the pairing is an accident of the file order.
const byTrigger = new Map(rows.map(r => [r.trigger, r]))
for (const r of rows) {
  const base = r.trigger.replace(/ no /, " ").replace(/^no /, "")
  if (base !== r.trigger && byTrigger.has(base) && r.pairs !== base) {
    wrong++
    console.error(`x line ${r.line} (${r.trigger}) is the negation of ${JSON.stringify(base)}, which is a trigger: mark them as a pair`)
  }
}
const pairs = rows.filter(r => r.pairs && r.mood === "subjunctive").length
console.log(`  minimal pairs: ${pairs}`)
if (pairs < 2) {
  wrong++
  console.error(`x ${pairs} minimal pair(s); the bank needs at least two, since only the doubt differs in a pair and that teaches the rule`)
}

// The premise of the whole drill: the form typed shows which mood was chosen.
// The expected form is always a cell of the table (the exercise is made from
// it, `Flashcards.Verbs.Mood.exercise`), and it is only a decision if the
// subjunctive cell is not the present one. Accents are forgiven in grading, so
// they must differ without them too. Held for every cell of the table, which
// is more than the bank wires, so that adding a verb needs no new proof.
const bare = form => form.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
let cells = 0
for (const verb of verbs) {
  for (const person of PERSONS.map(p => p.name)) {
    const present = verb.cells.get(`present.${person}`), subjunctive = verb.cells.get(`subjunctive.${person}`)
    cells++
    if (bare(present) === bare(subjunctive)) {
      wrong++
      console.error(`x ${verb.infinitive} ${person}: the subjunctive ${subjunctive} is the present ${present}, so the form typed would not say which mood was chosen`)
    }
  }
}
console.log(`  subjunctive differs from present, accents or not, in ${cells - wrong} of ${cells} cells`)

if (wrong) {
  console.error(`${wrong} problem(s) in ${CSV}`)
  process.exit(1)
}
