// Proves the conjugation table without anyone reading all of it.
//
//   node tools/check-verbs.mjs
//
// For every cell it works out what the *regular* form would be. Any verb and
// tense with a cell that differs is printed whole, the regular cells marked
// ·like this·: the deviations should be exactly the irregularities, and a
// regular cell among them is one to check was not regularised by mistake. A
// deviation that is not an irregularity is an error in the table, and a verb
// with no deviations at all is a verb that should not be in it. The output is
// the review. See #12 and #19.
//
// Exits non-zero only for structural failures - a gap, a duplicate, an unknown
// tense. Deviations are the point, not a failure.

import { TENSES, PERSONS, ENDINGS, loadTable, regular, CSV } from "./verb-source.mjs"

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
    const cells = PERSONS.map(({ name: person }) => {
      const form = verb.cells.get(`${tense}.${person}`)
      const expected = regular(verb.infinitive, tense, person)
      return { person, form, expected, deviates: form !== expected }
    })
    const differing = cells.filter(c => c.deviates).length
    if (!differing) {
      regularItems.push(`${verb.infinitive}.${tense}`)
      continue
    }
    any = true
    deviations += differing
    // The whole paradigm, so that a cell written as the regular form inside
    // an irregular tense is on the page to be looked at. Printing only the
    // deviations left `traducí` for `traduje` as nothing at all. See #19.
    const paradigm = cells.map(({ person, form, expected, deviates }) =>
      deviates ? `${person} ${form} (not ${expected})` : `${person} ·${form}·`)
    console.log(`${verb.infinitive.padEnd(width)}  ${tense.padEnd(11)}  ${paradigm.join(", ")}`)
  }
  if (!any) unexplained.push(`${verb.infinitive} conjugates entirely regularly - reconsider including it`)
}

console.log(`\n${verbs.length} verbs, ${verbs.length * TENSES.length * PERSONS.length} cells, ${deviations} deviate from the regular pattern`)

// What #16 would drop if deviations decide the schedule. Printed rather than
// acted on: see the caution in #12 about over-irregularising the imperfect.
console.log(`${regularItems.length} verb × tense items are entirely regular:`)
console.log(`  ${regularItems.join(" ")}`)

for (const u of unexplained) console.warn(`! ${u}`)
