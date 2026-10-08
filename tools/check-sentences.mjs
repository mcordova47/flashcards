// Checks the shift sentences against the conjugation table.
//
//   node tools/check-sentences.mjs
//
// Each row says which verb, tense and person its bracketed word is, so the
// table can say whether it is: `[tengo]` tagged `tener,present,1s` has to be
// what the table has there. A sentence that disagrees would still render, and
// ask a question whose premise is wrong, so unlike check-verbs this one fails.
// check-verbs cannot tell an irregularity from a mistake; this can, because
// the comparison is exact.
//
// It holds the sentences to the deck's vocabulary, as check-paraphrase holds
// the paraphrase corpus: every word a deck word, a regular inflection of one,
// or named in the row's Notes. The sentence is scaffolding, and scaffolding in
// words the learner has not met is a second exercise hiding in the first.
//
// It also lists every item whose pool has fewer than two sentences, since a
// later sighting of those has no different sentence to ask. See #16. For the
// person shift that takes three source persons per verb and tense, not two:
// a sentence cannot be asked into the person it is already in, so with two
// the persons they are in each have a pool of one. See #25.
//
// And it refuses two sentences around the same words, `[hacemos] la comida`
// and `[hacen] la comida`. They are two rows and one string: the pool is there
// so an item cannot be passed by remembering one, and asking both is asking
// the same thing twice. Of any two verbs, not only of one: the shifts never
// mix verbs in a pool, but error correction does, since its items are kinds
// of mistake. See #103.
//
// And for the same reason it refuses two that error correction would make
// one, which is a different string: correction puts a subject in front of a
// sentence that has none, so `[vengo] aquí` reads `yo [] aquí`, and so does
// `yo [estoy] aquí`.
//
// And every question whose answer, with its accents taken off, is another
// cell of the same verb and person: `llegué` and `llegue`, `busqué` and
// `busque`. `Exercise.matches` forgives a missing accent, so for those it
// cannot tell a phone typo from a mood error. Listed rather than refused -
// the answer is still right - but it is a question worth not asking.

import { PERSONS, loadTable } from "./verb-source.mjs"
import { CSV, SHIFTABLE, loadSentences } from "./sentence-source.mjs"
import { knownWords, unexplained } from "./deck-vocabulary.mjs"

const { verbs, errors: tableErrors } = loadTable()
const { sentences, errors } = loadSentences(verbs)
for (const e of [...tableErrors, ...errors]) console.error(`x ${e}`)
if (tableErrors.length || errors.length) process.exit(1)

const table = new Map(verbs.map(v => [v.infinitive, v.cells]))
const known = knownWords(verbs)
let wrong = 0
for (const s of sentences) {
  const expected = table.get(s.infinitive).get(`${s.tense.name}.${s.person.name}`)
  if (s.form !== expected) {
    wrong++
    console.error(`x line ${s.line}: [${s.form}] is tagged ${s.infinitive} ${s.tense.name} ${s.person.name}, which the table has as ${expected}`)
  }
  for (const word of unexplained(known, s.before + s.after, s.notes)) {
    wrong++
    console.error(`x line ${s.line}: ${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }
}

// Mirrors Flashcards.Verbs.Correction.subject, and Table.pronoun under it.
const PRONOUNS = { "1s": "yo", "2s": "tú", "3s": "él", "1p": "nosotros", "3p": "ellos" }
const subject = s => ["", "no"].includes(s.before.trim()) ? `${PRONOUNS[s.person.name]} ` : ""

const frames = new Map(), corrected = new Map()
for (const s of sentences) {
  const frame = `${s.before}[]${s.after}`
  const other = frames.get(frame)
  const correction = `${subject(s)}${frame}`
  const alike = corrected.get(correction)
  if (other) {
    wrong++
    console.error(`x line ${s.line}: [${s.form}] is line ${other.line}'s [${other.form}] with only the verb moved; a pool of the two asks one string`)
  } else if (alike) {
    wrong++
    console.error(`x line ${s.line}: [${s.form}] and line ${alike.line}'s [${alike.form}] are both ${correction} once error correction gives them a subject`)
  }
  frames.set(frame, frames.get(frame) ?? s)
  corrected.set(correction, alike ?? s)
}

const count = (pools, slug) => pools.set(slug, (pools.get(slug) ?? 0) + 1)

// Mirrors Flashcards.Verbs.Shift.exercises: every sentence, into every
// shiftable tense it is not already in.
const pools = new Map()
for (const s of sentences) {
  for (const target of SHIFTABLE.filter(t => t !== s.tense.name)) count(pools, `${s.infinitive}.${target}`)
}
const thin = [...pools].filter(([, n]) => n < 2)

// Mirrors Flashcards.Verbs.PersonShift.exercises: every sentence marked for
// it, into every person it is not already in.
const shiftable = sentences.filter(s => s.personShift)
const personPools = new Map()
for (const s of shiftable) {
  for (const target of PERSONS.filter(p => p.name !== s.person.name)) {
    count(personPools, `person.${s.infinitive}.${s.tense.name}.${target.name}`)
  }
}
const personThin = [...personPools].filter(([, n]) => n < 2)

// As Exercise.matches flattens.
const bare = form => form.normalize("NFD").replace(/[\u0301\u0308]/g, "").normalize("NFC")
const blurred = new Set()
for (const s of sentences) {
  const cells = table.get(s.infinitive)
  for (const target of SHIFTABLE.filter(t => t !== s.tense.name)) {
    const expected = cells.get(`${target}.${s.person.name}`)
    for (const [key, form] of cells) {
      const [tense, person] = key.split(".")
      if (person === s.person.name && form !== expected && bare(form) === bare(expected)) {
        blurred.add(`${s.infinitive}.${target} ${s.person.name}: ${expected}, but ${form} is its ${tense}`)
      }
    }
  }
}

const verbCount = new Set(sentences.map(s => s.infinitive)).size
console.log(`${sentences.length} sentences over ${verbCount} verbs, ${pools.size} items`)
if (thin.length) {
  console.log(`${thin.length} item(s) with one sentence, so a later sighting asks the same one:`)
  console.log(`  ${thin.map(([slug]) => slug).join(" ")}`)
}
console.log(`${shiftable.length} of them take a person shift, ${personPools.size} items`)
if (personThin.length) {
  console.log(`${personThin.length} person-shift item(s) with one sentence:`)
  console.log(`  ${personThin.map(([slug]) => slug).join(" ")}`)
}
if (blurred.size) {
  console.log(`${blurred.size} answer(s) that only an accent tells from another form of the verb:`)
  for (const b of blurred) console.log(`  ${b}`)
}
if (wrong) {
  console.error(`${wrong} problem(s) in ${CSV}`)
  process.exit(1)
}
