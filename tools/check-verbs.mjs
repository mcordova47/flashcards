// Proves the conjugation table without anyone reading all of it.
//
//   node tools/check-verbs.mjs
//
// For every cell it works out what the *regular* form would be, and prints
// only the cells that differ. That list should be exactly the irregularities:
// a deviation that is not one is an error in the table, and a verb with no
// deviations at all is a verb that should not be in it. The output is the
// review. See #12.
//
// Exits non-zero only for structural failures - a gap, a duplicate, an unknown
// tense. Deviations are the point, not a failure.

import { TENSES, PERSONS, loadTable, CSV } from "./verb-source.mjs"

// Present, preterite, imperfect and present subjunctive, by person, for each
// class. The subjunctive is built on the infinitive's stem rather than on the
// yo form, so `tenga` is reported: the rule that derives it is the thing a
// learner has to know.
const ENDINGS = {
  ar: {
    present: ["o", "as", "a", "amos", "an"],
    preterite: ["é", "aste", "ó", "amos", "aron"],
    imperfect: ["aba", "abas", "aba", "ábamos", "aban"],
    subjunctive: ["e", "es", "e", "emos", "en"],
  },
  er: {
    present: ["o", "es", "e", "emos", "en"],
    preterite: ["í", "iste", "ió", "imos", "ieron"],
    imperfect: ["ía", "ías", "ía", "íamos", "ían"],
    subjunctive: ["a", "as", "a", "amos", "an"],
  },
  ir: {
    present: ["o", "es", "e", "imos", "en"],
    preterite: ["í", "iste", "ió", "imos", "ieron"],
    imperfect: ["ía", "ías", "ía", "íamos", "ían"],
    subjunctive: ["a", "as", "a", "amos", "an"],
  },
}

const STRONG = "aeoáéó"
const ACCENTED = "áéíóú"
const PLAIN = { á: "a", é: "e", í: "i", ó: "o", ú: "u" }

// Syllables, as far as a written accent cares. Adjacent vowels share a
// syllable unless both are strong (a, e, o) or the weak one carries the
// accent - so `vió` is one syllable, which is the whole reason the 2010 rules
// write it `vio`, while `oí` is two.
const syllables = word => {
  let count = 0, previous = null
  for (const c of word) {
    if (!"aeiouáéíóúü".includes(c)) { previous = null; continue }
    const hiatus = previous !== null
      && ((STRONG.includes(previous) && STRONG.includes(c))
          || "íú".includes(previous) || "íú".includes(c))
    if (previous === null || hiatus) count++
    previous = c
  }
  return count
}

// A monosyllable takes no written accent (vio, dio, fue, vi), except for the
// diacritic ones that tell two words apart - and those are exactly what should
// show up as deviations, since `dé` is not the regular `de`.
const orthography = word =>
  syllables(word) === 1 ? [...word].map(c => PLAIN[c] ?? c).join("") : word

export const regular = (infinitive, tense, person) => {
  // `oír` and `reír` are -ir verbs whose infinitive carries a hiatus accent.
  const cls = infinitive.slice(-2).replace("í", "i")
  const stem = infinitive.slice(0, -2)
  const endings = ENDINGS[cls]
  if (!endings) return null
  return orthography(stem + endings[tense][PERSONS.findIndex(p => p.name === person)])
}

const { verbs, errors } = loadTable()

if (errors.length) {
  for (const e of errors) console.error(`x ${e}`)
  console.error(`${errors.length} structural problem(s) in ${CSV}`)
  process.exit(1)
}

const width = Math.max(...verbs.map(v => v.infinitive.length))
const unexplained = []
const regularItems = []
let deviations = 0

for (const verb of verbs) {
  if (!ENDINGS[verb.infinitive.slice(-2).replace("í", "i")]) {
    unexplained.push(`${verb.infinitive} does not end in -ar, -er or -ir`)
    continue
  }
  let any = false
  for (const { name: tense } of TENSES) {
    const differing = PERSONS
      .map(({ name: person }) => {
        const form = verb.cells.get(`${tense}.${person}`)
        const expected = regular(verb.infinitive, tense, person)
        return form === expected ? null : `${person} ${form} (not ${expected})`
      })
      .filter(Boolean)
    if (!differing.length) {
      regularItems.push(`${verb.infinitive}.${tense}`)
      continue
    }
    any = true
    deviations += differing.length
    console.log(`${verb.infinitive.padEnd(width)}  ${tense.padEnd(11)}  ${differing.join(", ")}`)
  }
  if (!any) unexplained.push(`${verb.infinitive} conjugates entirely regularly - reconsider including it`)
}

console.log(`\n${verbs.length} verbs, ${verbs.length * TENSES.length * PERSONS.length} cells, ${deviations} deviate from the regular pattern`)

// What #16 would drop if deviations decide the schedule. Printed rather than
// acted on: see the caution in #12 about over-irregularising the imperfect.
console.log(`${regularItems.length} verb × tense items are entirely regular:`)
console.log(`  ${regularItems.join(" ")}`)

for (const u of unexplained) console.warn(`! ${u}`)
