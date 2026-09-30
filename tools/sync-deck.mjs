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
import { LANGUAGES, SHEET, cardsIn, languagesFor, parseCsv } from "./deck-source.mjs"

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
    // The sheet exports CRLF and no trailing newline. Normalise both, or
    // every fetch rewrites every line, or reports one phantom difference at
    // the end of the file for ever.
    const normalised = body.replace(/\r\n/g, "\n").replace(/\n*$/, "\n")
    fs.writeFileSync(lang.csv, normalised)

    // Say *what* differs, not just how much. The sheet overwrites the
    // snapshot wholesale, so a row that has been improved here and never
    // pushed back comes silently undone - which is how four glosses that were
    // disambiguated with some care went back to being ambiguous.
    const was = previous.split("\n"), now = normalised.split("\n")
    const differing = now
      .map((line, i) => ({ line, before: was[i] }))
      .filter(row => row.line !== row.before && (row.line || row.before))
    console.log(`  wrote ${lang.csv}`
      + (differing.length ? ` - ${differing.length} row(s) differ from the local snapshot` : " - unchanged"))
    for (const { line, before } of differing.slice(0, 20)) {
      console.log(`    - ${before ?? "(absent)"}`)
      console.log(`    + ${line || "(absent)"}`)
    }
    if (differing.length > 20) console.log(`    ... and ${differing.length - 20} more`)

    // A slug is the only thing tying a card to its history, and the sheet
    // overwrites the snapshot wholesale, so a cell edited by mistake or a
    // column pasted one row out would silently rekey cards. Matched by word,
    // not rank: a row added or removed shifts every rank below it without
    // changing any card, and a deleted or respelled word has no slug here to
    // keep. What is left is a word still in the deck whose slug changed.
    const before = cardsIn(previous, lang.column), after = cardsIn(normalised, lang.column)
    if (!droppingPins) {
      const had = new Map(before.map(c => [c.word, c.slug])), has = new Map(after.map(c => [c.word, c.slug]))
      const lost = [...had].filter(([word, slug]) => slug && has.has(word) && has.get(word) !== slug)
      if (lost.length) {
        fail(`the fetch changed the slug of ${lost.length} word(s) still in the deck:\n`
           + lost.slice(0, 20).map(([word, slug]) =>
               `    ${word}  was keyed ${JSON.stringify(slug)}, now ${JSON.stringify(has.get(word))}`).join("\n")
           + (lost.length > 20 ? `\n    ... and ${lost.length - 20} more` : "")
           + `\n  Put them back in the Slug column of the ${lang.tab} tab, or rerun with --drop-pins `
           + `if it was deliberate - a card with a new slug starts its history over.`)
      }
    }

    // What this fetch did to cards' identities, paired by slug - which is an
    // identity now, not a guess. This is the moment to say it: the person
    // made the edit and still knows whether it was a respelling or a
    // replacement, and only they can tell those apart. After this it is one
    // line among every earlier respelling (see the tree-wide count below).
    const wasBySlug = new Map(before.filter(c => c.slug).map(c => [c.slug, c]))
    const isBySlug = new Set(after.map(c => c.slug))
    if (wasBySlug.size) {
      const list = (items, line) => items.slice(0, 20).map(line).join("\n")
        + (items.length > 20 ? `\n      ... and ${items.length - 20} more` : "")
      const reworded = after.filter(c => wasBySlug.has(c.slug) && wasBySlug.get(c.slug).word !== c.word)
      const fresh = after.filter(c => c.slug && !wasBySlug.has(c.slug))
      const gone = [...wasBySlug.values()].filter(c => !isBySlug.has(c.slug))
      if (reworded.length) {
        console.log(`  ! ${reworded.length} card(s) changed word and keep their history, box and direction:\n`
          + list(reworded, c => `      #${c.rank}  ${wasBySlug.get(c.slug).word} -> ${c.word}`)
          + `\n    Right for a respelling. If one is a different word, it will be asked as the old card was -`
          + `\n    in production, never shown, if that card had graduated. To start it fresh instead, put its`
          + `\n    own word in its Slug cell in the ${lang.tab} tab and fetch again with --drop-pins.`)
      }
      if (fresh.length) {
        console.log(`  ! ${fresh.length} card(s) start fresh, under a slug the snapshot did not have:\n`
          + list(fresh, c => `      #${c.rank}  ${c.slug}`))
      }
      if (gone.length) {
        console.log(`  ! ${gone.length} slug(s) left the deck, and their history with them:\n`
          + list(gone, c => `      ${c.slug}  (was #${c.rank}, ${c.word})`)
          + `\n    Right for a deleted word. If one was respelled instead, put the old slug back in its`
          + `\n    Slug cell in the ${lang.tab} tab and fetch again with --drop-pins to keep its history.`)
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
  // Required, on every row. The slug is what progress is keyed by, and it is
  // written down rather than derived from the word so that correcting a
  // spelling cannot quietly change which card it is. An empty one is refused
  // rather than filled in from the word, which is the silent case over again.
  const slugAt = header.indexOf("Slug")
  if (slugAt < 0) fail(`there is no Slug column. Every card needs one: it is what its history is keyed by.`)

  const cards = body.map((cells, i) => {
    const rank = Number((cells[0] ?? "").trim())
    const english = (cells[1] ?? "").trim()
    const foreign = (cells[2] ?? "").trim()
    const example = exampleAt < 0 ? "" : (cells[exampleAt] ?? "").trim()
    const slug = (cells[slugAt] ?? "").trim()
    if (!Number.isInteger(rank)) fail(`row ${i + 2} has a non-integer Order: ${cells[0]}`)
    if (!english) fail(`row ${i + 2} has an empty English side`)
    if (!foreign) fail(`row ${i + 2} has an empty ${lang.column} side`)
    // Verbatim, not normalised. Stripping accents merges este/éste and
    // schön/schon; lowercasing would merge German Sie and sie in a deck that
    // carried both. The word is already required unique, so it needs nothing
    // doing to it.
    return { rank, english, foreign, example, slug }
  })

  cards.forEach((c, i) => {
    if (c.rank !== i + 1) fail(`Order is not contiguous: expected ${i + 1}, got ${c.rank}`)
  })

  const unslugged = cards.filter(c => !c.slug)
  if (unslugged.length) {
    fail(`${unslugged.length} card(s) have no slug:\n`
       + unslugged.slice(0, 20).map(c => `    #${c.rank}  ${c.foreign}`).join("\n")
       + (unslugged.length > 20 ? `\n    ... and ${unslugged.length - 20} more` : "")
       + `\n  Fill each Slug cell in the ${lang.tab} tab with the word itself. A slug is never `
       + `filled in for you, because that is how a respelling used to lose a card's history.`)
  }

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
  // this is not an error - but it is also what a word replaced by a different
  // one looks like, and those are indistinguishable to a machine. The replaced
  // card inherits the old one's box and direction - asked in production,
  // unseen, if the old card had graduated, and a miss resets the box but never
  // the direction - so changing its slug is how to start it fresh instead.
  // The fetch that makes one says so, card by card, while the person still
  // knows which it was. Here it is only counted: every respelling leaves one
  // for good, and a list that grows forever is a list nobody reads.
  const rekeyed = cards.filter(c => c.slug !== c.foreign).length
  if (rekeyed) {
    warnings.push(`${rekeyed} card(s) are keyed by an earlier spelling of their word - `
                + `expected after a respelling; the fetch that made each one listed it`)
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
  // Leading commas, the way the rest of the codebase writes a list: the
  // separator opens the line its element is on, rather than sitting alone on
  // one of its own and doubling the file.
  const entries = cards
    .map(c => `{ rank: Rank ${c.rank}, slug: Slug "${escape(c.slug)}"`
             + `, english: "${escape(c.english)}", word: "${escape(c.foreign)}"`
             + `, example: "${escape(c.example)}" }`)
    .join("\n  , ")

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
  [ ${entries}
  ]
`)

  console.log(`[${lang.code}] wrote ${out} (${cards.length} cards, fingerprint ${fingerprint})`)
  for (const w of warnings) console.warn(`  ! ${w}`)
  console.log(`  ${collisions.length} English sides map to >1 ${lang.name} word`)
}
