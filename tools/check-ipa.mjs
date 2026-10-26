// Refuses an IPA column that is missing, malformed or unmarked (#175).
//
//   node tools/check-ipa.mjs
//
// For every `IPA <tag>` column of every deck CSV, on every row:
//   - it is not empty;
//   - it uses only the characters that dialect's inventory allows
//     (tools/ipa-source.mjs), which is what catches a `θ` in es-MX, a slash or
//     bracket pasted in from a dictionary, or a combining mark;
//   - it has the same words as the word side, one for one, split the same way
//     (a slashed row, a phrase and a `(se)` row are each transcribed word by
//     word);
//   - every word of more than one syllable has exactly one stress mark, and
//     one of a single syllable has none, and the mark is before a vowel;
//   - no slash, bracket or space inside a word: only the word side's own
//     " / " and a trailing "(se)" are allowed.
//
// It does not check *where* the mark falls, which would need a syllabifier.
//
// It cannot say a transcription is the right one for its word. That is a
// person's review, and this is only what survives it.

import fs from "fs"
import { LANGUAGES, parseCsv } from "./deck-source.mjs"
import { alphabet, ipaColumns, syllables, wordParts } from "./ipa-source.mjs"

let failed = false
const fail = msg => { console.error(`x ${msg}`); failed = true }

for (const lang of LANGUAGES) {
  const [header, ...body] = parseCsv(fs.readFileSync(lang.csv, "utf-8"))
  const columns = ipaColumns(header)
  if (!columns.length) { console.log(`[${lang.code}] no IPA column`); continue }
  const wordAt = header.indexOf(lang.column)

  for (const { tag, column } of columns) {
    const allowed = alphabet(tag)
    if (!allowed) { fail(`[${lang.code}] ${column}: no inventory for "${tag}" in tools/ipa-source.mjs`); continue }
    const at = header.indexOf(column)
    let bad = 0
    const problem = (rank, word, msg) => { bad++; fail(`[${lang.code}] ${column} #${rank} ${word}: ${msg}`) }

    for (const cells of body) {
      if (cells.length === 1 && cells[0] === "") continue
      const rank = cells[0]
      const word = (cells[wordAt] ?? "").trim()
      const ipa = (cells[at] ?? "").trim()
      if (!ipa) { problem(rank, word, "no transcription"); continue }

      const stray = [...ipa].filter(c => !allowed.has(c))
      if (stray.length) problem(rank, word, `${JSON.stringify(ipa)} has ${stray.map(c => `U+${c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")} ${c}`).join(", ")}, not in the ${tag} inventory`)

      const have = wordParts(ipa), want = wordParts(word)
      if (have.length !== want.length) {
        problem(rank, word, `${JSON.stringify(ipa)} has ${have.length} word(s) where the word side has ${want.length}`)
        continue
      }
      if (ipa.includes("(se)") !== word.includes("(se)")) problem(rank, word, `${JSON.stringify(ipa)} and the word side disagree about (se)`)

      // The separator and the clitic are the word side's own and are the only
      // slashes and brackets a stored value may have. Anything left in a word
      // is a delimiter pasted in from a dictionary, or a stray one.
      if ((cells[at] ?? "") !== ipa) problem(rank, word, `${JSON.stringify(ipa)} has leading or trailing space`)
      for (const part of have) {
        if (/[\/()\s]/.test(part)) problem(rank, word, `${JSON.stringify(part)} has a slash, bracket or space inside a word`)
        if (part.includes("ˈ") && !/ˈ[^aeiou]*[aeiou]/.test(part)) problem(rank, word, `${JSON.stringify(part)} has a stress mark with no vowel after it`)
        const marks = [...part].filter(c => c === "ˈ").length
        const n = syllables(part)
        if (n > 1 && marks !== 1) problem(rank, word, `${JSON.stringify(part)} has ${n} syllables and ${marks} stress marks`)
        if (n <= 1 && marks) problem(rank, word, `${JSON.stringify(part)} is one syllable and should carry no stress mark`)
      }
    }
    if (!bad) console.log(`[${lang.code}] ${column}: ${body.filter(c => c.length > 1).length} rows ok`)
  }
}

if (failed) process.exit(1)
