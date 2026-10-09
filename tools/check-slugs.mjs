// Refuses a change that rekeys a card: a word still in the deck whose slug is
// not the one it had on the base branch.
//
//   node tools/check-slugs.mjs                  against origin/main
//   node tools/check-slugs.mjs --base <ref>     against another ref
//   node tools/check-slugs.mjs --drop-pins      report, but exit zero
//
// A slug is the only thing tying a card to its history, so one edited by
// mistake, or a column pasted a row out, would silently hand a card somebody
// else's box and direction. Matched by word, not rank: a row added or removed
// shifts every rank below it without changing any card, and a deleted or
// respelled word has no slug on this side to keep. What is left is a word
// still in the deck whose slug changed.
//
// It compares against a ref and never against HEAD: once a change is
// committed, HEAD already has it and the comparison sees nothing (#79).
// A replacement, word and slug changed together, passes - the word is no
// longer the same word. `--drop-pins` is for the slug edited on its own,
// deliberately, to start a card fresh; it lets through every change, so make
// that edit its own pull request.

import { execFileSync } from "child_process"
import fs from "fs"
import { LANGUAGES, cardsIn } from "./deck-source.mjs"

const args = process.argv.slice(2)
const droppingPins = args.includes("--drop-pins")
const at = args.indexOf("--base")
const base = at < 0 ? "origin/main" : args[at + 1]

if (!base) {
  console.error("x --base needs a ref")
  process.exit(1)
}

const git = (...a) => execFileSync("git", a, { encoding: "utf-8", stdio: ["ignore", "pipe", "pipe"] })

try {
  git("rev-parse", "--verify", "--quiet", `${base}^{commit}`)
} catch {
  console.error(`x ${base} is not a ref here, so there is nothing to compare against.`
    + ` Fetch it (git fetch origin main) or name another with --base.`)
  process.exit(1)
}

let lostAny = false
for (const lang of LANGUAGES) {
  let previous
  try { previous = git("show", `${base}:${lang.csv}`) }
  catch { console.log(`[${lang.code}] ${lang.csv} is not on ${base}; nothing to compare`); continue }

  const before = cardsIn(previous, lang.column)
  const after = cardsIn(fs.readFileSync(lang.csv, "utf-8"), lang.column)
  const had = new Map(before.map(c => [c.word, c.slug]))
  const has = new Map(after.map(c => [c.word, c.slug]))
  const lost = [...had].filter(([word, slug]) => slug && has.has(word) && has.get(word) !== slug)

  if (!lost.length) { console.log(`[${lang.code}] no slug changed on a word still in the deck`); continue }
  lostAny = true
  console.error(`x [${lang.code}] ${lost.length} word(s) still in the deck changed slug since ${base}:\n`
    + lost.slice(0, 20).map(([word, slug]) =>
        `    ${word}  was keyed ${JSON.stringify(slug)}, now ${JSON.stringify(has.get(word))}`).join("\n")
    + (lost.length > 20 ? `\n    ... and ${lost.length - 20} more` : "")
    + `\n  Put them back in the Slug column of ${lang.csv}, or run with --drop-pins if you meant it - `
    + `a card whose slug changes takes that slug's history instead of its own.`)
}

if (lostAny && !droppingPins) process.exit(1)
