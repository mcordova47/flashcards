// Keeps a card's history when its spelling changes.
//
//   node tools/rename.mjs              report every word that changed since HEAD
//   node tools/rename.mjs es libertad libertád   was libertad, now reads libertád: keep its history
//   node tools/rename.mjs es libertad --new      a different word: pin its new spelling, fresh start
//   node tools/rename.mjs es 472                 by rank, which checks nothing
//
// A card can be named by rank or by its old spelling, and the new spelling
// asserted after it. Only the assertion protects anything. Changes are found
// by pairing old and new words at the same rank, so a row added or removed
// above a respelling reports it against the neighbouring card - and a rank, or
// an old spelling alone, pins whatever that pairing says. The new spelling,
// typed from what was actually changed, fails instead. No word in either deck
// is numeric, so a rank and a word cannot clash.
//
// Either way it only ever records a change the sheet already made. Spelling
// flows one way, sheet to CSV to module; writing the new spelling from here
// would make this a second source of it, and the next --fetch would undo it.
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
import { LANGUAGES, changesIn, formatRow, languagesFor, parseCsv, wordsIn } from "./deck-source.mjs"

const args = process.argv.slice(2)
const fresh = args.includes("--new")
const [only, handle, asserted] = args.filter(a => !a.startsWith("--"))

const die = message => { console.error(`x ${message}`); process.exit(1) }

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
      const state = c.pin === c.from ? " (pinned)"
        : c.pin === c.to ? " (a new word)"
        : c.pin ? ` (pinned to ${JSON.stringify(c.pin)}!)` : ""
      console.log(`  #${c.rank}  ${c.from} -> ${c.to}${state}`)
    }
  }
  if (!found) {
    console.log("No word changed spelling since the last commit.")
  } else {
    console.log("\nFor each one, decide whether the history should follow:")
    console.log("  node tools/rename.mjs <lang> <old> <new>   a respelling - keep the history")
    console.log("  node tools/rename.mjs <lang> <old> --new   a different word - start fresh")
    console.log("Type <new> from what you changed in the sheet, not from the list above. It pairs")
    console.log("words by rank, so a row added or removed above a respelling puts it on the")
    console.log("neighbouring card, and the assertion is what catches that. A rank works in")
    console.log("place of <old>, but checks nothing.")
  }
  process.exit(0)
}

const [lang] = languagesFor(only)
if (!lang) die(`Unknown language "${only}". Known: ${LANGUAGES.map(l => l.code).join(", ")}`)

if (!handle) die(`Expected a rank or a word after "${only}"`)

const changes = changesIn(lang)

// A word is looked up as the old spelling first, since that is what names a
// change. Failing that it may be a card nothing has happened to - which is
// fine for clearing a stale pin with --new - or the *new* spelling of one that
// has changed, which is a slip worth catching rather than guessing past.
const byWord = word => {
  const change = changes.find(c => c.from === word)
  if (change) return change.rank
  const [rank] = [...wordsIn(fs.readFileSync(lang.csv, "utf-8"), lang.column)].find(([, w]) => w === word) ?? []
  if (rank === undefined) die(`no card in ${lang.csv} reads or read ${JSON.stringify(word)}. Run without arguments to see what changed.`)
  const renamed = changes.find(c => c.rank === rank)
  if (renamed) {
    die(`${JSON.stringify(word)} is what #${rank} reads now. Name it by the spelling it had, `
      + `${JSON.stringify(renamed.from)}, or by its rank.`)
  }
  return rank
}

const rank = /^\d+$/.test(handle) ? Number(handle) : byWord(handle)
const change = changes.find(c => c.rank === rank)

if (asserted !== undefined && change?.to !== asserted) {
  die(change
    ? `#${rank} ${change.from} now reads ${JSON.stringify(change.to)}, not ${JSON.stringify(asserted)}. `
      + `The deck has moved since you looked - run without arguments to see what changed.`
    : `#${rank} has not changed spelling since the last commit, so it cannot have become ${JSON.stringify(asserted)}.`)
}

if (fresh && change) {
  // Pinned to its own spelling, which keys it exactly as no pin would. The
  // filled cell is the point: it is what tells sync-deck this change was
  // decided, where an empty one looks the same as a change nobody noticed.
  const row = setPin(lang, rank, change.to)
  console.log(`#${rank} ${change.from} -> ${change.to}`)
  console.log(`  pinned to its new spelling in ${lang.csv}, so it starts fresh.`)
  console.log(`\n  Put the same value in the sheet, or the next --fetch will drop it:`)
  console.log(`    ${lang.tab} tab, row ${row}, Slug column: ${change.to}`)
  console.log(`\n  Then: npm run sync-deck ${lang.code}`)
  process.exit(0)
}

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
