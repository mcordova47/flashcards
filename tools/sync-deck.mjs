// Generates a deck module per language from its committed CSV snapshot.
//
//   node tools/sync-deck.mjs              regenerate every deck
//   node tools/sync-deck.mjs de           just German
//   node tools/sync-deck.mjs --fetch      pull each sheet tab first, then regenerate
//   node tools/sync-deck.mjs de --fetch   pull just that tab
//
// The sheet is the authoring tool; the app never talks to it at runtime.

import fs from "fs"
import crypto from "crypto"
import { LANGUAGES, languagesFor, parseCsv, pinsIn } from "./deck-source.mjs"

const args = process.argv.slice(2)
const fetching = args.includes("--fetch")
const droppingPins = args.includes("--drop-pins")
const only = args.find(a => !a.startsWith("--"))
const chosen = languagesFor(only)

if (!chosen.length) {
  console.error(`Unknown language "${only}". Known: ${LANGUAGES.map(l => l.code).join(", ")}`)
  process.exit(1)
}

const SHEET_ERRORS = /^#(REF|N\/A|VALUE|ERROR|NAME|DIV\/0|NUM|NULL)[!?]?$/i

for (const lang of chosen) {
  const fail = msg => { console.error(`x [${lang.code}] ${msg}`); process.exit(1) }
  const warnings = []

  if (fetching) {
    const url = `https://docs.google.com/spreadsheets/d/${SHEET}/export?format=csv&gid=${lang.gid}`
    console.log(`downloading [${lang.code}] tab ${lang.gid}`)
    const res = await fetch(url)
    if (!res.ok) fail(`sheet fetch failed: ${res.status} ${res.statusText}`)
    const body = await res.text()
    if (!body.startsWith("Order,")) fail("the tab did not return the expected CSV header")
    const previous = fs.existsSync(lang.csv) ? fs.readFileSync(lang.csv, "utf-8") : ""
    // The sheet exports CRLF. Normalise, or every fetch rewrites every line
    // and buries the real change.
    const normalised = body.replace(/\r\n/g, "\n")
    fs.writeFileSync(lang.csv, normalised)
    const was = previous.split("\n"), now = normalised.split("\n")
    const differing = now.filter((line, i) => line !== was[i]).length
    // Loud, because the sheet overwrites local edits and decks get edited in
    // both places.
    console.log(`  wrote ${lang.csv}`
      + (differing ? ` - ${differing} row(s) differ from the local snapshot` : " - unchanged"))

    // A pinned slug is the only thing tying a renamed card to its history, and
    // the sheet overwrites the snapshot wholesale. Losing one is silent - the
    // slug simply goes back to matching the word, so nothing downstream can
    // tell - which makes this the one place it can be caught.
    if (!droppingPins) {
      const had = pinsIn(previous), has = pinsIn(normalised)
      const lost = [...had].filter(([rank, pin]) => has.get(rank) !== pin)
      if (lost.length) {
        fail(`the fetch dropped ${lost.length} pinned slug(s) that ${lang.csv} had:\n`
           + lost.map(([rank, pin]) => `    #${rank} was keyed ${JSON.stringify(pin)}`).join("\n")
           + `\n  Add them to the Slug column of the ${lang.tab} tab, or rerun with --drop-pins `
           + `to orphan that history deliberately.`)
      }
    }
  }

  const [header, ...body] = parseCsv(fs.readFileSync(lang.csv, "utf-8"))
  const want = ["Order", "English", lang.column]
  if (want.some((c, i) => header[i] !== c)) {
    fail(`expected the first columns to be ${want.join(", ")}, got ${header.slice(0, 3).join(", ")}`)
  }

  // Optional, and found by name: the decks do not agree on column count.
  const exampleAt = header.indexOf("Example")
  // Also optional, and usually empty. A slug is only written down when a word
  // is renamed and its history should follow; otherwise the word is the slug.
  const slugAt = header.indexOf("Slug")

  const cards = body.map((cells, i) => {
    const rank = Number((cells[0] ?? "").trim())
    const english = (cells[1] ?? "").trim()
    const foreign = (cells[2] ?? "").trim()
    const example = exampleAt < 0 ? "" : (cells[exampleAt] ?? "").trim()
    const pinned = slugAt < 0 ? "" : (cells[slugAt] ?? "").trim()
    if (!Number.isInteger(rank)) fail(`row ${i + 2} has a non-integer Order: ${cells[0]}`)
    if (!english) fail(`row ${i + 2} has an empty English side`)
    if (!foreign) fail(`row ${i + 2} has an empty ${lang.column} side`)
    // Verbatim, not normalised. Stripping accents merges este/éste and
    // schön/schon; lowercasing would merge German Sie and sie in a deck that
    // carried both. The word is already required unique, so it needs nothing
    // doing to it.
    return { rank, english, foreign, example, slug: pinned || foreign }
  })

  cards.forEach((c, i) => {
    if (c.rank !== i + 1) fail(`Order is not contiguous: expected ${i + 1}, got ${c.rank}`)
  })

  // Spreadsheet coercions. Sheets decides the string "true" is a boolean and
  // exports it as TRUE; `verdadero` was glossed that way from the very first
  // import and nobody noticed for months. Lowercase "true" is a legitimate
  // gloss, so only the shouting form is a coercion.
  for (const c of cards) {
    for (const [side, value] of [["English", c.english], [lang.column, c.foreign]]) {
      if (value === "TRUE" || value === "FALSE") {
        fail(`#${c.rank} ${side} is ${value} - the spreadsheet turned a word into a boolean. `
           + `Force the cell to text, or untick "Convert text to numbers, dates, and formulas" on import.`)
      }
      if (SHEET_ERRORS.test(value)) fail(`#${c.rank} ${side} is ${value}, a spreadsheet error value`)
      if (value.length > 1 && value === value.toUpperCase() && /[A-Z]{2}/.test(value)) {
        warnings.push(`#${c.rank} ${side} is all capitals (${JSON.stringify(value)}) - often a coercion`)
      }
    }
  }

  // A prompt containing its own answer makes the production card free. A whole
  // gloss equal to the foreign side is a true cognate and fine.
  for (const c of cards) {
    const stem = c.foreign.replace(/\(se\)$/, "").trim()
    if (stem.length < 3 || c.english.toLowerCase() === c.foreign.toLowerCase()) continue
    if (new RegExp(`\\b${stem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i").test(c.english)) {
      warnings.push(`#${c.rank} the gloss ${JSON.stringify(c.english)} contains its own answer`)
    }
  }

  const seen = new Map()
  for (const c of cards) {
    if (seen.has(c.foreign)) {
      fail(`duplicate ${lang.column} side ${JSON.stringify(c.foreign)} at #${seen.get(c.foreign)} `
         + `and #${c.rank}. Recognition prompts with the foreign side, so it has to be unique.`)
    }
    seen.set(c.foreign, c.rank)
  }

  const slugs = new Map()
  for (const c of cards) {
    if (slugs.has(c.slug)) {
      fail(`duplicate slug ${JSON.stringify(c.slug)} at #${slugs.get(c.slug)} and #${c.rank}. `
         + `Progress is keyed by slug, so two cards sharing one would share a history.`)
    }
    slugs.set(c.slug, c.rank)
  }

  // A slug outliving its spelling is exactly what the Slug column is for, so
  // this is not an error - but it is also what an accidentally reused slug
  // looks like, and those are indistinguishable to a machine.
  for (const c of cards) {
    if (c.slug !== c.foreign) {
      warnings.push(`#${c.rank} is keyed ${JSON.stringify(c.slug)} but reads `
                  + `${JSON.stringify(c.foreign)} - intended after a rename, wrong if the word was replaced`)
    }
  }

  const byEnglish = new Map()
  for (const c of cards) byEnglish.set(c.english, [...(byEnglish.get(c.english) ?? []), c.foreign])
  const collisions = [...byEnglish.values()].filter(v => v.length > 1)

  // Identifies what a rank *means*. Progress is keyed by slug now, so this no
  // longer guards saved history; what is left is placing the rank-keyed
  // payloads that predate v5, and refusing a backup from the wrong deck to a
  // version of the app too old to say which language it is. Excludes the
  // English side, because rewording a gloss moves nothing.
  const fingerprint = crypto.createHash("sha256")
    .update(cards.map(c => `${c.rank}\u0000${c.foreign}`).join("\n"))
    .digest("hex").slice(0, 12)

  const escape = s => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  const entries = cards
    .map(c => `  { rank: Rank ${c.rank}, slug: Slug "${escape(c.slug)}"`
             + `, english: "${escape(c.english)}", word: "${escape(c.foreign)}"`
             + `, example: "${escape(c.example)}" }`)
    .join("\n  ,\n")

  const out = `src/Flashcards/Data/Deck/${lang.module}.purs`
  fs.writeFileSync(out, `-- | GENERATED by tools/sync-deck.mjs - do not edit.
-- |
-- | Source: ${lang.csv} (${cards.length} words, ${lang.note}).
module Flashcards.Data.Deck.${lang.module}
  ( deck
  , fingerprint
  )
  where

import Flashcards.Types.Card (Card, Rank(..), Slug(..))

-- | Content hash of what each rank means. Progress is keyed by slug, so this
-- | is no longer what protects it - it certifies that a rank still names the
-- | word it named, which is all that placing a pre-v5 payload needs.
fingerprint :: String
fingerprint = "${fingerprint}"

-- | The index into this deck is meaningful: it is the order cards are
-- | introduced in.
deck :: Array Card
deck =
  [
${entries}
  ]
`)

  console.log(`[${lang.code}] wrote ${out} (${cards.length} cards, fingerprint ${fingerprint})`)
  for (const w of warnings) console.warn(`  ! ${w}`)
  console.log(`  ${collisions.length} English sides map to >1 ${lang.name} word`)
}
