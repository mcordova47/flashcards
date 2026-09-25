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
