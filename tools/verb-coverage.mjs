// A recommendation for every cell of the conjugation table: drill it, leave it
// for later, or leave it out. Writes data/es-verb-coverage.csv.
//
//   node tools/verb-coverage.mjs
//
// Derived, and an argument rather than a fact - it is the input to #27, which
// asks which of the 760 cells earn a place. `npm run sync` regenerates it,
// and then tools/sync-coverage.mjs generates the verdicts into a module the
// app can read (#96), so CI's drift check covers both.
//
// The reasoning, in the order it is applied:
//
//   1. A cell that DEVIATES from the regular pattern is an irregularity you
//      have to memorise. Drill it.
//   2. A cell that is regular except for the 2010 monosyllable rule - `vio`,
//      `dio`, `rio`, `dé` - is regular in its endings and wrong-looking to a
//      learner. The accent IS the lesson. Drill it.
//   3. A regular cell of a verb that is irregular ALL OVER is where
//      over-correction happens: knowing `tengo, tuve, tenga` is exactly what
//      makes someone distrust `tenía`, which is regular. #12 flags this and it
//      is counterintuitive enough to act on. Drill it.
//
//      The line is drawn at half the verb's cells, which is the most arguable
//      number here and is deliberately a round one. It puts `tener` (14 of 20)
//      on the drill side and `andar` (5, all in the preterite) on the other -
//      nobody distrusts `andaba` because `anduve` surprised them once.
//   4. Any other regular cell is the ending rule applied. One rule, not five
//      cells. Leave it out.
//   5. Any of the above on a verb the deck does not teach, or teaches past
//      rank 500, is real but rarely met. Later, not never.
//
// The `Recovers` column is a second, rival signal, reported beside the
// recommendation rather than folded into it. Rule 3 says a regular cell is
// hard because the verb reads as irregular and gets over-corrected. The rival
// says it is hard for a different reason: you know a form, not a lemma.
//
// Eighteen of the thirty-eight change their stem in the present, which is the
// form you meet most — `puedo`, `vuelvo`, `quiero`. To build anything on the
// infinitive you first have to get back to it, and if you cannot you build on
// the wrong stem: `encuentro` gives `encuentraba` rather than `encontraba`.
// A cell marked `Recovers` is one of a stem-changing verb whose form uses the
// infinitive's stem - the nosotros forms and most of the imperfect - so
// producing it means recovering the lemma first.
//
// The two disagree about fifteen verbs. Which is right is a question for
// `missed` once the drills have been used; until then both are on the record.
// See #27.

import fs from "fs"
import { loadTable, ENDINGS, PERSONS, TENSES, regular } from "./verb-source.mjs"
import { parseCsv } from "./deck-source.mjs"

const OUT = "data/es-verb-coverage.csv"
const COMMON = 500
// Of 20 cells. Above this a verb reads as irregular, so its regular tenses are
// distrusted and worth confirming. See rule 3.
const PERVASIVE = 10

const { verbs, errors } = loadTable()
if (errors.length) {
  for (const e of errors) console.error(`x ${e}`)
  process.exit(1)
}

// Deck rank per verb, so "how often would you meet this" is a number.
const rank = new Map()
for (const [n, , spanish] of parseCsv(fs.readFileSync("data/es-1000.csv", "utf-8")).slice(1)) {
  for (const part of (spanish ?? "").split(/[,/]/)) {
    const w = part.trim().replace("(se)", "")
    if (w && !rank.has(w)) rank.set(w, Number(n))
  }
}

// What the endings alone would give, before the monosyllable rule. The
// difference between this and `regular` is exactly the orthographic cases.
const naive = (infinitive, tense, person) => {
  const cls = infinitive.slice(-2).replace("í", "i")
  return infinitive.slice(0, -2) + ENDINGS[cls][tense][PERSONS.findIndex(p => p.name === person)]
}

const deviations = verb =>
  TENSES.flatMap(({ name: t }) => PERSONS.map(({ name: p }) =>
    verb.cells.get(`${t}.${p}`) !== regular(verb.infinitive, t, p))).filter(Boolean).length

// The stem the infinitive offers, and whether the present keeps it. `oír`
// keeps `o` and merely grows a `y`; `reír` does not keep `re`.
const stemOf = infinitive => infinitive.slice(0, -2)
const changesStem = verb =>
  !verb.cells.get("present.3s").startsWith(stemOf(verb.infinitive))

const rows = []
for (const verb of verbs) {
  const r = rank.get(verb.infinitive) ?? null
  const common = r !== null && r <= COMMON
  const pervasive = deviations(verb) >= PERVASIVE
  const shifts = changesStem(verb)
  for (const { name: tense } of TENSES) {
    const cells = PERSONS.map(({ name: person }) => {
      const form = verb.cells.get(`${tense}.${person}`)
      const plain = regular(verb.infinitive, tense, person)
      return { person, form, deviates: form !== plain, orthographic: form === plain && form !== naive(verb.infinitive, tense, person) }
    })
    for (const c of cells) {
      let recommend, why
      if (c.deviates) [recommend, why] = ["drill", "irregular; the form has to be memorised"]
      else if (c.orthographic) [recommend, why] = ["drill", "regular endings, but the accent rule makes it look wrong"]
      else if (pervasive) [recommend, why] = ["drill", "regular, but the verb is not, so this is where it gets over-corrected"]
      else [recommend, why] = ["skip", "regular, on a verb that is regular here; this is the ending rule, not a fact"]
      if (recommend === "drill" && !common) {
        recommend = "later"
        why = `${why}; ${r === null ? "the deck does not teach this verb" : `rank ${r}, so rarely met`}`
      }
      // Needs the lemma back before it can be built. See the note above.
      const recovers = shifts && c.form.startsWith(stemOf(verb.infinitive))
      rows.push([verb.infinitive, r ?? "", tense, c.person, c.form,
                 c.deviates ? "yes" : "", recovers ? "yes" : "", recommend, why])
    }
  }
}

const quote = v => /[",]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v)
fs.writeFileSync(OUT,
  "Infinitive,Rank,Tense,Person,Form,Deviates,Recovers,Recommend,Why\n"
  + rows.map(r => r.map(quote).join(",")).join("\n") + "\n")

const tally = rows.reduce((a, r) => ({ ...a, [r[7]]: (a[r[7]] ?? 0) + 1 }), {})
console.log(`wrote ${OUT} (${rows.length} cells)`)
for (const k of ["drill", "later", "skip"]) console.log(`  ${String(tally[k] ?? 0).padStart(3)}  ${k}`)

const recovers = rows.filter(r => r[6] === "yes")
const disputed = recovers.filter(r => r[7] === "skip").length
console.log(`\n${recovers.length} need the lemma recovered first, across ${new Set(recovers.map(r => r[0])).size} stem-changing verbs`)
console.log(`  ${disputed} of them this recommendation leaves out — where the two signals disagree`)
