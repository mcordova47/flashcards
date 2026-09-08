// Keeps a card's history when its spelling changes.
//
//   node tools/rename.mjs              report every word that changed since HEAD
//   node tools/rename.mjs es 472       #472 was renamed: pin its old spelling
//   node tools/rename.mjs es 472 --new #472 is a different word: no pin, fresh start
//
// Progress is keyed by a card's slug, and a slug is the foreign word's
// spelling unless the CSV's Slug column pins something else. So correcting a
// spelling silently orphans that card's history — everyone studying it loses
// the word's past and meets it again as new — unless the old spelling is
// pinned first. That has come up three times in this deck's life: `concrete`
// to `concreto`, and two accent corrections.
//
// Which of the two a change is cannot be decided by machine. `concrete` to
// `concreto` and `concrete` to `armario` are the same edit; only the person
// making it knows whether the history should follow. So this reports, and
// waits to be told.

import fs from "fs"
import { execFileSync } from "child_process"
import { LANGUAGES, formatRow, languagesFor, parseCsv, pinsIn, wordsIn } from "./deck-source.mjs"

const args = process.argv.slice(2)
const fresh = args.includes("--new")
const [only, rankArg] = args.filter(a => !a.startsWith("--"))

const die = message => { console.error(`x ${message}`); process.exit(1) }

const committed = path => {
  try {
    return execFileSync("git", ["show", `HEAD:${path}`], { encoding: "utf-8" })
  } catch {
    return null // Not committed yet; there is nothing to have renamed away from.
  }
}

// A rank whose foreign word differs from the committed snapshot, and whose old
// spelling is nowhere in the new one. A word that merely moved rank is not a
// rename — the slug travels with the card, which is the point of the rekey.
const changesIn = lang => {
  const now = fs.readFileSync(lang.csv, "utf-8")
  const then = committed(lang.csv)
  if (then === null) return []
  const was = wordsIn(then, lang.column)
  const has = wordsIn(now, lang.column)
  const present = new Set(has.values())
  const pinned = pinsIn(now)
  return [...has]
    .filter(([rank, word]) => was.has(rank) && was.get(rank) !== word && !present.has(was.get(rank)))
    .map(([rank, word]) => ({ rank, from: was.get(rank), to: word, pin: pinned.get(rank) ?? null }))
}

// Writes one field on one row, adding the Slug column if the CSV has none.
// Line by line rather than a full round-trip, so the diff stays two lines.
const setPin = (lang, rank, pin) => {
  const lines = fs.readFileSync(lang.csv, "utf-8").split("\n")
  const header = parseCsv(lines[0])[0]
  let at = header.indexOf("Slug")
  if (at < 0) {
    at = header.length
    lines[0] = formatRow([...header, "Slug"])
  }
  const i = lines.findIndex((line, n) => n > 0 && line && Number(parseCsv(line)[0][0]) === rank)
  if (i < 0) die(`no row in ${lang.csv} at #${rank}`)
  const cells = parseCsv(lines[i])[0]
  while (cells.length <= at) cells.push("")
  cells[at] = pin
  lines[i] = formatRow(cells)
  fs.writeFileSync(lang.csv, lines.join("\n"))
  return i + 1
}

if (!only) {
  let found = 0
  for (const lang of LANGUAGES) {
    const changes = changesIn(lang)
    if (!changes.length) continue
    found += changes.length
    console.log(`\n[${lang.code}] ${changes.length} word(s) changed since the last commit`)
    for (const c of changes) {
      const state = c.pin === c.from ? " (pinned)" : c.pin ? ` (pinned to ${JSON.stringify(c.pin)}!)` : ""
      console.log(`  #${c.rank}  ${c.from} -> ${c.to}${state}`)
    }
  }
  if (!found) {
    console.log("No word changed spelling since the last commit.")
  } else {
    console.log("\nFor each one, decide whether the history should follow:")
    console.log("  node tools/rename.mjs <lang> <rank>        a respelling - keep the history")
    console.log("  node tools/rename.mjs <lang> <rank> --new  a different word - start fresh")
  }
  process.exit(0)
}

const [lang] = languagesFor(only)
if (!lang) die(`Unknown language "${only}". Known: ${LANGUAGES.map(l => l.code).join(", ")}`)

const rank = Number(rankArg)
if (!Number.isInteger(rank)) die(`Expected a rank, got ${JSON.stringify(rankArg ?? "")}`)

const change = changesIn(lang).find(c => c.rank === rank)

if (fresh) {
  // Clearing a pin is how a mistaken one is undone, so it is allowed even
  // where nothing changed.
  const row = setPin(lang, rank, "")
  console.log(`#${rank} left unpinned - it will be keyed by its own spelling and start fresh.`)
  console.log(`  Clear the Slug column of row ${row} in the ${lang.tab} tab too.`)
  process.exit(0)
}

if (!change) {
  die(`#${rank} has not changed spelling since the last commit, so there is nothing to pin. `
    + `Run without arguments to see what did.`)
}

const row = setPin(lang, rank, change.from)
console.log(`#${rank} ${change.from} -> ${change.to}`)
console.log(`  pinned to ${JSON.stringify(change.from)} in ${lang.csv}, so its history follows.`)
console.log(`\n  Put the same value in the sheet, or the next --fetch will drop it:`)
console.log(`    ${lang.tab} tab, row ${row}, Slug column: ${change.from}`)
console.log(`\n  Then: npm run sync-deck ${lang.code}`)
