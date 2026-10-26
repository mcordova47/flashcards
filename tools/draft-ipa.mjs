// Drafts the `IPA es-MX` column of data/es-1000.csv from the spelling, and
// lists the rows a person has to look at (#175).
//
//   node tools/draft-ipa.mjs            print the draft and the doubts, write nothing
//   node tools/draft-ipa.mjs --write    add the column to the CSV, once
//
// A drafter can only follow spelling, so what it writes is a draft and not an
// answer: no tool can say an IPA string is the right one for a word. Once the
// column is in the CSV, the CSV is the source and a hand correction is just an
// edit to it; this is not run again over a column that has been reviewed, and
// `--write` refuses to.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { draftRow, doubts } from "./ipa-source.mjs"

const TAG = "es-MX"
const csv = "data/es-1000.csv"
const text = fs.readFileSync(csv, "utf-8")
const [header, ...body] = parseCsv(text)
const wordAt = header.indexOf("Español")

const rows = body.map(cells => {
  const foreign = cells[wordAt].trim()
  return { rank: Number(cells[0]), foreign, ipa: draftRow(foreign), doubts: doubts(foreign) }
})

if (process.argv.includes("--write")) {
  if (header.includes(`IPA ${TAG}`)) {
    console.error(`x ${csv} already has an IPA ${TAG} column. It has been reviewed by now; edit it directly.`)
    process.exit(1)
  }
  const lines = text.split("\n")
  const out = lines.map((line, i) => i === 0 ? `${line},IPA ${TAG}` : (line === "" ? line : `${line},${rows[i - 1].ipa}`))
  fs.writeFileSync(csv, out.join("\n"))
  console.log(`wrote IPA ${TAG} for ${rows.length} rows`)
} else {
  for (const r of rows) console.log(`${r.rank}\t${r.foreign}\t${r.ipa}${r.doubts.length ? `\t# ${r.doubts.join(", ")}` : ""}`)
}
