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

const SHEET = "1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w"

// One entry per language. `column` names the foreign side in the CSV, and
// `gid` identifies the tab — a tab *name* cannot be used, because the export
// endpoint silently falls back to the first sheet for a name it does not know.
const LANGUAGES = [
  {
    code: "es",
    name: "Spanish",
    gid: "886210546",
    column: "Español",
    csv: "data/es-1000.csv",
    module: "Spanish",
    note: "ordered by frequency, most common first",
  },
  {
    code: "de",
    name: "German",
    gid: "1432606036",
    column: "Deutsch",
    csv: "data/de-1000.csv",
    module: "German",
    note: "a course vocabulary list, A1 then A2, so rank is curriculum position rather than frequency",
  },
]

// RFC 4180: fields may be quoted, quotes escape as "".
const parseCsv = text => {
  const rows = []
  let row = [], field = "", quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (c === '"') quoted = false
      else field += c
    } else if (c === '"') quoted = true
    else if (c === ",") { row.push(field); field = "" }
    else if (c === "\n") { row.push(field); rows.push(row); row = []; field = "" }
    else if (c !== "\r") field += c
  }
  if (field !== "" || row.length) { row.push(field); rows.push(row) }
  return rows
}

const args = process.argv.slice(2)
const fetching = args.includes("--fetch")
const only = args.find(a => !a.startsWith("--"))
const chosen = only
  ? LANGUAGES.filter(l => l.code === only || l.module.toLowerCase() === only.toLowerCase())
  : LANGUAGES

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
  }

  const [header, ...body] = parseCsv(fs.readFileSync(lang.csv, "utf-8"))
  const want = ["Order", "English", lang.column]
  if (want.some((c, i) => header[i] !== c)) {
    fail(`expected the first columns to be ${want.join(", ")}, got ${header.slice(0, 3).join(", ")}`)
  }

  const cards = body.map((cells, i) => {
    const rank = Number((cells[0] ?? "").trim())
    const english = (cells[1] ?? "").trim()
    const foreign = (cells[2] ?? "").trim()
    if (!Number.isInteger(rank)) fail(`row ${i + 2} has a non-integer Order: ${cells[0]}`)
    if (!english) fail(`row ${i + 2} has an empty English side`)
    if (!foreign) fail(`row ${i + 2} has an empty ${lang.column} side`)
    return { rank, english, foreign }
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

  const byEnglish = new Map()
  for (const c of cards) byEnglish.set(c.english, [...(byEnglish.get(c.english) ?? []), c.foreign])
  const collisions = [...byEnglish.values()].filter(v => v.length > 1)

  // Identifies what a rank *means*. Deliberately excludes the English side:
  // progress is keyed by rank, so the only change that can corrupt it is a
  // word moving rank. Rewording a gloss cannot.
  const fingerprint = crypto.createHash("sha256")
    .update(cards.map(c => `${c.rank}\u0000${c.foreign}`).join("\n"))
    .digest("hex").slice(0, 12)

  const escape = s => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  const entries = cards
    .map(c => `  { rank: Rank ${c.rank}, english: "${escape(c.english)}", word: "${escape(c.foreign)}" }`)
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

import Flashcards.Types.Card (Card, Rank(..))

-- | Content hash of what each rank means. Progress is keyed by rank, so a deck
-- | whose rows were renumbered is a different deck as far as saved progress is
-- | concerned.
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
