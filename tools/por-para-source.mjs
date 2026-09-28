// The por / para sentences, and what a row of them is allowed to be. Shared by
// tools/sync-por-para.mjs, which generates from them, and
// tools/check-por-para.mjs, which holds them to the deck. See #18.
//
// A row is a sentence with the preposition in brackets, the English that
// says which sense it is, the item it belongs to, and a note for anything
// that needs one:
//
//   lo hice [por] ti,I did it because of you.,cause-purpose,"ti: ..."
//
// The English is not a gloss. `lo hice [ ] ti` takes either preposition, and
// the English is the only thing that says which - so it is the prompt.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"

export const CSV = "data/es-por-para.csv"

// Each item's id, as the CSV and the slug spell it, its constructor in
// Flashcards.Verbs.PorPara, which this has to agree with, and what it is.
//
// Most are contrasts, two senses that English says with one word, and are
// asked both ways. A few are senses with no opposite (#43): `dos veces por
// semana` has no `para semana` to be mistaken for, but still invites `para`
// from someone who has not met the rule. Those name the one preposition they
// take, as `takes`.
//
// The kind is here and not a column of the CSV because it belongs to the item,
// not the sentence - every row of `per` takes `por` by definition - and a
// column could disagree with itself within one pool. And an item without
// `takes` is a contrast, so a contrast that loses a side is still refused: the
// only way to a one-sided pool is to say, here, that it is meant to be one.
export const ITEMS = {
  "cause-purpose": { constructor: "CausePurpose" },
  "duration-deadline": { constructor: "DurationDeadline" },
  "through-towards": { constructor: "ThroughTowards" },
  "exchange-recipient": { constructor: "ExchangeRecipient" },
  "per": { constructor: "Per", takes: "por" },
  "means": { constructor: "Means", takes: "por" },
}

export const PREPOSITIONS = { por: "Por", para: "Para" }

const HEADER = ["Sentence", "English", "Item", "Notes"]

// Lowercase and unpunctuated, as the shift sentences are: the frame is
// scaffolding either side of a box, not a sentence to be read as prose.
const WORDS = /^[a-zñáéíóúü]+( [a-zñáéíóúü]+)*$/
const SHAPE = /^((?:[^\[\]]+ )?)\[([^\[\]]+)\]((?: [^\[\]]+)?)$/

// Reads the bank and refuses anything structurally wrong: a sentence without
// exactly one bracketed word, a bracketed word that is neither por nor para,
// a character the page does not expect, an item that is not one, or
// English that another row already asks.
//
// Whether the rest is deck vocabulary, and whether each item has the sides it
// should, is tools/check-por-para.mjs.
export const loadRows = () => {
  const errors = []
  const [header, ...body] = parseCsv(fs.readFileSync(CSV, "utf-8"))
  if (HEADER.some((c, i) => header[i] !== c) || header.length !== HEADER.length) {
    return { rows: [], errors: [`expected the header ${HEADER.join(",")}, got ${header.join(",")}`] }
  }

  const seen = new Map()
  const rows = []

  body.forEach((cells, i) => {
    const line = i + 2
    if (cells.length !== HEADER.length) {
      errors.push(`line ${line} has ${cells.length} fields, not ${HEADER.length}`)
      return
    }
    const [text, english, item, notes] = cells
    const shape = text.match(SHAPE)
    const plain = text.replace(/[\[\]]/g, "")

    if (!shape) errors.push(`line ${line}: ${JSON.stringify(text)} needs exactly one [bracketed] word`)
    else if (!PREPOSITIONS[shape[2]]) errors.push(`line ${line}: [${shape[2]}] is not por or para`)
    if (!WORDS.test(plain)) errors.push(`line ${line}: ${JSON.stringify(plain)} is not lowercase words separated by single spaces`)
    if (!english) errors.push(`line ${line}: a row needs the English that says which sense it is`)
    if (!ITEMS[item]) errors.push(`line ${line}: ${JSON.stringify(item)} is not one of ${Object.keys(ITEMS).join(", ")}`)
    // The English is the prompt, so two rows with the same English are one
    // question - and if their answers differ, a question with two answers.
    // The same *Spanish* is allowed, and is the point of a minimal pair:
    // `lo hice [por] ti` and `lo hice [para] ti`.
    if (seen.has(english)) errors.push(`line ${line}: ${JSON.stringify(english)} is already the English on line ${seen.get(english)}`)
    seen.set(english, line)

    if (shape) {
      rows.push({ line, text, before: shape[1], answer: shape[2], after: shape[3], english, item, notes })
    }
  })

  return { rows, errors }
}
