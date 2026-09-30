// The deck sources, and the CSV handling tools/sync-deck.mjs and the tests
// share.

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

// Each word's slug, for every row that has both. Keyed by word rather than
// rank, because rank is a position: a row added or removed above a card moves
// it without changing what it is.
export const slugsByWord = (text, column) => {
  const [header, ...body] = parseCsv(text)
  const wordAt = (header ?? []).indexOf(column), slugAt = (header ?? []).indexOf("Slug")
  const slugs = new Map()
  if (wordAt < 0) return slugs
  for (const cells of body) {
    const word = (cells[wordAt] ?? "").trim()
    if (word) slugs.set(word, slugAt < 0 ? "" : (cells[slugAt] ?? "").trim())
  }
  return slugs
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
