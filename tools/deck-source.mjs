// The deck sources, and the CSV handling shared by tools/sync-deck.mjs and
// tools/rename.mjs.

export const SHEET = "1vz4CgmSxP7fFmoa-uzjXPmHckkjSfl2evmRyG5EsH5w"

// One entry per language. `column` names the foreign side in the CSV, and
// `gid` identifies the tab — a tab *name* cannot be used, because the export
// endpoint silently falls back to the first sheet for a name it does not know.
export const LANGUAGES = [
  {
    code: "es",
    name: "Spanish",
    gid: "886210546",
    tab: "es-1000",
    column: "Español",
    csv: "data/es-1000.csv",
    module: "Spanish",
    note: "ordered by frequency, most common first",
  },
  {
    code: "de",
    name: "German",
    gid: "1432606036",
    tab: "de-1000",
    column: "Deutsch",
    csv: "data/de-1000.csv",
    module: "German",
    note: "a course vocabulary list, A1 then A2, so rank is curriculum position rather than frequency",
  },
]

export const languagesFor = only =>
  only
    ? LANGUAGES.filter(l => l.code === only || l.module.toLowerCase() === only.toLowerCase())
    : LANGUAGES

// RFC 4180: fields may be quoted, quotes escape as "".
export const parseCsv = text => {
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

const quote = field => /["\n,]/.test(field) ? `"${field.replace(/"/g, '""')}"` : field

// One row back to one line. Rows are rewritten a line at a time rather than
// the file being round-tripped, so editing a slug touches one line in the diff
// instead of reflowing a thousand.
export const formatRow = fields => fields.map(quote).join(",")

// A card's pinned slug, by rank, for every row that has one. Empty for a CSV
// with no Slug column, which is every deck that has never had a rename.
export const pinsIn = text => {
  const [header, ...body] = parseCsv(text)
  const at = (header ?? []).indexOf("Slug")
  const pins = new Map()
  if (at < 0) return pins
  for (const cells of body) {
    const rank = Number((cells[0] ?? "").trim())
    const pin = (cells[at] ?? "").trim()
    if (Number.isInteger(rank) && pin) pins.set(rank, pin)
  }
  return pins
}

// The foreign side of every row, by rank.
export const wordsIn = (text, column) => {
  const [header, ...body] = parseCsv(text)
  const at = (header ?? []).indexOf(column)
  const words = new Map()
  if (at < 0) return words
  for (const cells of body) {
    const rank = Number((cells[0] ?? "").trim())
    if (Number.isInteger(rank)) words.set(rank, (cells[at] ?? "").trim())
  }
  return words
}
