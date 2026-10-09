// Glosses that share a content word without being the same string, listed
// worst-first for a person to rule on. See #95.
//
//   node tools/near-collisions.mjs [es|de]
//
// A report, not a gate. `isCanonical` compares glosses as strings, so two cards
// worded differently are both asked in production even when a reader cannot
// tell their prompts apart. Grouping on shared words finds candidates; it
// cannot decide them — `to work` against `work (job)` is a different question,
// `to agree` against `to agree (remember)` is the same one — so the ceiling it
// prints is a list to read, not a number to drive to zero.
//
// Its floor is the cases where the English really is shared. Where the deck
// chose different English for the same Spanish sense (`mitad` half, `medio`
// medium, `media` average) it sees nothing, and the notes are the only channel.

import fs from "fs"
import { languagesFor, parseCsv } from "./deck-source.mjs"

const STOP = new Set(["to", "the", "a", "an", "of", "is", "be", "in", "on", "for", "at", "with", "by", "and", "or"])
// Crude: enough to join agree/agrees/agreed, not a stemmer.
const stem = w => w.replace(/(ing|ed|es|s)$/, "")
const words = gloss =>
  gloss.replace(/\([^)]*\)/g, " ").toLowerCase().split(/[^a-z']+/)
    .filter(w => w && !STOP.has(w)).map(stem)

const lang = languagesFor(process.argv[2] ?? "es")[0]
const [header, ...rows] = parseCsv(fs.readFileSync(lang.csv, "utf-8"))
const at = n => header.indexOf(n)
const cards = rows.filter(r => r[at("English")] && r[at(lang.column)]).map(r => ({
  rank: r[at("Order")], english: r[at("English")], word: r[at(lang.column)],
}))

const byWord = new Map()
for (const c of cards) for (const w of new Set(words(c.english)))
  byWord.set(w, [...(byWord.get(w) ?? []), c])

// Keep a group only where it holds more than one distinct gloss; identical
// glosses are already grouped by the app.
const groups = [...byWord].map(([w, cs]) => ({ w, cs }))
  .filter(({ cs }) => new Set(cs.map(c => c.english)).size > 1)
  .sort((a, b) => b.cs.length - a.cs.length || a.w.localeCompare(b.w))

console.log(`[${lang.code}] ${groups.length} shared content words across differing glosses`)
for (const { w, cs } of groups) {
  console.log(`\n${w}`)
  for (const c of cs) console.log(`  #${c.rank} ${c.word}  '${c.english}'`)
}
