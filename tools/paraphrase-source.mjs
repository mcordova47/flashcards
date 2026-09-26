// The paraphrase prompts, and what a row of them is allowed to be. Shared by
// the tools that read them, so that whatever refuses a row refuses it once:
// tools/check-paraphrase.mjs checks them against the table and the deck.
//
// A row is an id, an English prompt, a model answer, the verb, tense and
// person the answer uses, the one trap the prompt exists to spring, and the
// wrong choice a learner reaches for:
//
//   door-open,"How would you tell me the door is open?","La puerta está abierta.",estar,present,3s,verb,ser,
//
// Whether the model answer *uses* the form it claims, and whether the rest is
// deck vocabulary, is not decided here - that is tools/check-paraphrase.mjs.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { PERSONS, TENSES } from "./verb-source.mjs"

export const CSV = "data/es-paraphrase.csv"

export const TRAPS = { verb: "OnVerb", tense: "OnTense" }

const HEADER = ["Id", "Prompt", "Model", "Verb", "Tense", "Person", "Trap", "Against", "Notes"]

// The row's identity, and what its progress is keyed by, so it is frozen once
// written and never derived from the prompt or the model - #22 expects those
// to be reworded, and a reworded row is the same item. Same lesson as slugs
// against ranks; see Flashcards.Types.Card.
const ID = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/

// Reads the corpus and refuses anything structurally wrong: an id that is not
// one or is used twice, a verb the table does not have, a tense or person
// that is not one, a trap that is neither, or an `against` that is not a
// plausible wrong choice of the kind the trap names. `table` is
// `loadTable().verbs`, since the table's spelling of an infinitive is the one
// every other file has to use.
export const loadPrompts = table => {
  const errors = []
  const [header, ...body] = parseCsv(fs.readFileSync(CSV, "utf-8"))
  if (HEADER.some((c, i) => header[i] !== c) || header.length !== HEADER.length) {
    return { prompts: [], errors: [`expected the header ${HEADER.join(",")}, got ${header.join(",")}`] }
  }

  const infinitives = new Set(table.map(v => v.infinitive))
  const tenses = TENSES.map(t => t.name), persons = PERSONS.map(p => p.name)
  const ids = new Map()
  const prompts = []

  body.forEach((cells, i) => {
    const line = i + 2
    if (cells.length !== HEADER.length) {
      errors.push(`line ${line} has ${cells.length} fields, not ${HEADER.length}`)
      return
    }
    const [id, asked, model, verb, tense, person, trap, against, notes] = cells
    const fail = message => errors.push(`line ${line} (${model}): ${message}`)

    if (!ID.test(id)) fail(`${JSON.stringify(id)} is not a lowercase hyphenated id`)
    else if (ids.has(id)) fail(`the id ${id} is already used on line ${ids.get(id)}`)
    ids.set(id, line)
    if (!asked || !model) fail("a row needs both a prompt and a model answer")
    if (!infinitives.has(verb)) fail(`${verb} is not one of the ${infinitives.size} verbs in the table`)
    if (!tenses.includes(tense)) fail(`unknown tense ${JSON.stringify(tense)}`)
    if (!persons.includes(person)) fail(`unknown person ${JSON.stringify(person)}`)

    // One trap, and the other targets not also decisions. A verb trap sits in
    // the present, or the learner is choosing a tense as well and the rubric
    // cannot say which mistake they made.
    if (trap === "verb") {
      if (!infinitives.has(against) || against === verb) fail(`against a verb trap, ${JSON.stringify(against)} should be another verb in the table`)
      if (tense !== "present") fail(`a verb trap should sit in the present, not the ${tense}`)
    } else if (trap === "tense") {
      if (!tenses.includes(against) || against === tense) fail(`against a tense trap, ${JSON.stringify(against)} should be another tense`)
    } else {
      fail(`trap should be one of ${Object.keys(TRAPS).join(", ")}, not ${JSON.stringify(trap)}`)
    }

    prompts.push({
      line, id, asked, model, verb, against, notes,
      tense: TENSES.find(t => t.name === tense),
      person: PERSONS.find(p => p.name === person),
      trap,
    })
  })

  return { prompts, errors }
}
