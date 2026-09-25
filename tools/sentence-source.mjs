// The tense-shift sentences, and what a row of them is allowed to be. Shared
// by tools/sync-sentences.mjs, which generates from them, and
// tools/check-sentences.mjs, which checks them against the table.
//
// A row is a sentence with its verb in brackets, what that verb is, and a
// note for anything that needs one - a word from outside the deck, say:
//
//   no [puedo] dormir,poder,present,1s,
//
// The brackets are the position tag. They are what the page leaves a gap
// for, and they read as the sentence rather than as a count of words.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { PERSONS, TENSES } from "./verb-source.mjs"

export const CSV = "data/es-sentences.csv"

const HEADER = ["Sentence", "Infinitive", "Tense", "Person", "Notes"]

// Lowercase and unpunctuated, as the exercise shows them. A capital or a full
// stop would have to be moved onto whichever form replaces the verb, and the
// sentence is scaffolding - it is not worth the machinery. See #16.
const WORDS = /^[a-zñáéíóúü]+( [a-zñáéíóúü]+)*$/
const SHAPE = /^((?:[^\[\]]+ )?)\[([^\[\]]+)\]((?: [^\[\]]+)?)$/

// Not the subjunctive, which is a mood and not a tense. See
// `Flashcards.Verbs.Shift.tenses`, which this has to agree with.
export const SHIFTABLE = ["present", "preterite", "imperfect"]

// Reads the bank and refuses anything structurally wrong: a sentence without
// exactly one bracketed word, a character the page does not expect, a tense
// a shift cannot reach, or a verb the table does not have. `table` is
// `loadTable().verbs`, since the table's spelling of an infinitive is the one
// every other file has to use.
//
// Whether the bracketed word is the *right* form, and whether the rest is deck
// vocabulary, is not decided here - that is tools/check-sentences.mjs.
export const loadSentences = table => {
  const errors = []
  const [header, ...body] = parseCsv(fs.readFileSync(CSV, "utf-8"))
  if (HEADER.some((c, i) => header[i] !== c) || header.length !== HEADER.length) {
    return { sentences: [], errors: [`expected the header ${HEADER.join(",")}, got ${header.join(",")}`] }
  }

  const infinitives = new Set(table.map(v => v.infinitive))
  const persons = PERSONS.map(p => p.name)
  const seen = new Set()
  const sentences = []

  body.forEach((cells, i) => {
    const line = i + 2
    if (cells.length !== HEADER.length) {
      errors.push(`line ${line} has ${cells.length} fields, not ${HEADER.length}`)
      return
    }
    const [text, infinitive, tense, person, notes] = cells
    const shape = text.match(SHAPE)
    const plain = text.replace(/[\[\]]/g, "")

    if (!shape) errors.push(`line ${line}: ${JSON.stringify(text)} needs exactly one [bracketed] word`)
    else if (shape[2].includes(" ")) errors.push(`line ${line}: [${shape[2]}] is more than one word`)
    if (!WORDS.test(plain)) errors.push(`line ${line}: ${JSON.stringify(plain)} is not lowercase words separated by single spaces`)
    // ir, not ir(se): the deck's spelling is a gloss, the table's is the verb.
    if (!infinitives.has(infinitive)) errors.push(`line ${line}: ${JSON.stringify(infinitive)} is not a verb in the table`)
    if (!SHIFTABLE.includes(tense)) errors.push(`line ${line}: ${JSON.stringify(tense)} is not one of ${SHIFTABLE.join(", ")}`)
    if (!persons.includes(person)) errors.push(`line ${line}: unknown person ${JSON.stringify(person)}`)
    if (seen.has(plain)) errors.push(`line ${line}: ${JSON.stringify(plain)} is already in the bank`)
    seen.add(plain)

    if (shape) {
      sentences.push({
        line,
        before: shape[1],
        form: shape[2],
        after: shape[3],
        infinitive,
        tense: TENSES.find(t => t.name === tense),
        person: PERSONS.find(p => p.name === person),
        notes,
      })
    }
  })

  return { sentences, errors }
}
