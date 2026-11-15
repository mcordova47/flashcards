// The trigger sentences the subjunctive is drilled with, and what a row of
// them is allowed to be. Shared by tools/sync-triggers.mjs, which generates
// from them, and tools/check-triggers.mjs, which holds them to the deck and to
// the conjugation table. See #230 and #241.
//
// Two files, because two different things are written once and used often.
//
// data/es-triggers.csv is the bank of *triggers*: the kinds of words that
// decide a mood, each with the mood it demands, the kind of meaning that
// demands it, the reason said after an answer, the forms it is allowed to
// take in a sentence, and the trigger it is a minimal pair with:
//
//   no creer que,subjunctive,doubt,not believing it...,creer que,no creo que/1s|no crees que/2s|...
//
// data/es-trigger-sentences.csv is the bank of *sentences*, written by hand
// whole, each with a blank where the verb goes:
//
//   esperar que,querer,1s,el maestro espera que yo ___ aprender más cada día,,
//
// A sentence says which trigger it uses, which verb is blanked and which
// person the blank is. It never says the form: the form is the conjugation
// table's cell for that verb and person, in the tense the trigger's mood
// calls for, and `Flashcards.Verbs.Mood` reads it there. So the mood, the
// group and the reason cannot disagree with the sentence, because they are the
// trigger's and not the sentence's, and the answer cannot be mistyped, because
// nobody types it.
//
// What a sentence has to be is the content rule, and no tool can check the
// whole of it: that it is natural Mexican Spanish and means something. What a
// tool can check is in tools/check-triggers.mjs, and a reviewer reads the rest.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"
import { PERSONS } from "./verb-source.mjs"

export const CSV = "data/es-triggers.csv"
export const SENTENCES = "data/es-trigger-sentences.csv"

export const MOODS = { subjunctive: "Subjunctive", indicative: "Indicative" }

// The kinds of meaning, in the order they are met, each with the mood it
// demands, what the page calls it when it says why, and its constructor in
// `Flashcards.Verbs.Mood`. The mood belongs to the group and not to the row,
// so a row cannot be filed under a kind that contradicts its own mood. The
// indicative groups are there so that always typing the subjunctive loses.
export const GROUPS = {
  "wish": { mood: "subjunctive", label: "wish or request", constructor: "Wish" },
  "doubt": { mood: "subjunctive", label: "doubt or denial", constructor: "Doubt" },
  "emotion": { mood: "subjunctive", label: "emotion", constructor: "Emotion" },
  "judgment": { mood: "subjunctive", label: "impersonal judgment", constructor: "Judgment" },
  "purpose-time": { mood: "subjunctive", label: "purpose, condition or future time", constructor: "PurposeTime" },
  "certainty": { mood: "indicative", label: "belief or certainty", constructor: "Certainty" },
  "fact": { mood: "indicative", label: "a fact or a reason", constructor: "Fact" },
}

// Where the coverage needs a floor (see check-triggers).
export const MIN_PER_GROUP = 3
export const MIN_INDICATIVE_SHARE = 0.25
// Of the sentences: enough minimal pairs to be a feature, no trigger more than a
// sixth of them, and a pool for a verb and person that is not so short that
// the same sentence comes round every other sighting.
export const MIN_PAIRS = 15
export const MAX_TRIGGER_SHARE = 1 / 6
export const MIN_CELL = 4

const HEADER = ["Trigger", "Mood", "Group", "Reason", "Pairs", "Forms", "Notes"]
const WORDS = /^[a-zñáéíóúü]+( [a-zñáéíóúü]+)*$/

// Reads the bank and refuses anything structurally wrong: a trigger that is
// not lowercase words, a mood or group that is not one, a group that
// contradicts the mood, a missing reason, a trigger already asked, or a pair
// that points nowhere, to the same mood, or at itself.
//
// Whether the words are deck vocabulary and whether the groups are broad
// enough is tools/check-triggers.mjs.
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
    const [trigger, mood, group, reason, pairs, forms, notes] = cells
    if (!WORDS.test(trigger)) errors.push(`line ${line}: ${JSON.stringify(trigger)} is not lowercase words separated by single spaces`)
    if (!MOODS[mood]) errors.push(`line ${line}: ${JSON.stringify(mood)} is not one of ${Object.keys(MOODS).join(", ")}`)
    if (!GROUPS[group]) errors.push(`line ${line}: ${JSON.stringify(group)} is not one of ${Object.keys(GROUPS).join(", ")}`)
    else if (GROUPS[group].mood !== mood) errors.push(`line ${line}: ${group} demands the ${GROUPS[group].mood}, so ${JSON.stringify(trigger)} cannot be ${mood}`)
    if (!reason.trim()) errors.push(`line ${line}: ${JSON.stringify(trigger)} has no reason, and the reason is what is shown after the answer`)
    // The same words twice are one question, whatever else differs.
    if (seen.has(trigger)) errors.push(`line ${line}: ${JSON.stringify(trigger)} is already the trigger on line ${seen.get(trigger)}`)
    seen.set(trigger, line)
    const parsed = parseForms(forms, line, errors)
    rows.push({ line, trigger, mood, group, reason, pairs, forms: parsed, notes })
  })

  const byTrigger = new Map(rows.map(r => [r.trigger, r]))
  for (const r of rows.filter(r => r.pairs)) {
    const other = byTrigger.get(r.pairs)
    if (!other) errors.push(`line ${r.line}: ${JSON.stringify(r.trigger)} pairs with ${JSON.stringify(r.pairs)}, which is not a trigger`)
    else if (other.mood === r.mood) errors.push(`line ${r.line}: ${JSON.stringify(r.trigger)} pairs with a trigger of the same mood; a minimal pair differs in it`)
    else if (other.pairs !== r.trigger) errors.push(`line ${r.line}: ${JSON.stringify(r.trigger)} pairs with ${JSON.stringify(r.pairs)}, which does not pair back`)
  }

  return { rows, errors }
}

const personNames = PERSONS.map(p => p.name)

// `quiero que/1s|quieres que/2s|...`: the words a sentence may use for the
// trigger, each with the person of the main clause's subject where it has one
// (`/1s`). A `*` stands for one or more words, so that `voy a * hasta que`
// takes `voy a esperar hasta que`. A form with no person is an impersonal
// (`es importante que`) or has no subject of its own (`para que`).
//
// The person is there so that a sentence cannot give the main clause and the
// blank the same subject, which Spanish does with the infinitive.
const parseForms = (text, line, errors) => {
  if (!text.trim()) {
    errors.push(`line ${line}: no forms; a trigger is only usable in a sentence if it says what it looks like there`)
    return []
  }
  return text.split("|").map(entry => {
    const [words, person] = entry.split("/")
    if (!/^[a-zñáéíóúü]+( (?:\*|[a-zñáéíóúü]+))*$/.test(words)) errors.push(`line ${line}: form ${JSON.stringify(words)} is not lowercase words, or * for any words`)
    if (person !== undefined && !personNames.includes(person)) errors.push(`line ${line}: form ${JSON.stringify(entry)} has the unknown person ${JSON.stringify(person)}`)
    const pattern = new RegExp(`(?<![a-zñáéíóúü])${words.split(" ").map(w => w === "*" ? "[a-zñáéíóúü]+(?: [a-zñáéíóúü]+)*" : w).join(" ")}(?![a-zñáéíóúü])`)
    return { words, person: person ?? null, pattern }
  })
}

const BLANK = "___"
const SENTENCE_HEADER = ["Trigger", "Verb", "Person", "Sentence", "Pair", "Notes"]
const TEXT = /^[a-zñáéíóúü_]+( [a-zñáéíóúü_]+)*$/

// Reads the sentences and refuses anything structurally wrong: a trigger that
// is not in the bank, a verb the table does not have, a sentence without
// exactly one blank, with the blank first, or without the trigger's words
// before it, a trigger's form used where it is not wanted, or the same
// sentence twice. `rows` is what `loadRows` returned and `table` is
// `loadTable().verbs`.
//
// Whether the sentence is plausible, deck vocabulary, right for its person and
// balanced is tools/check-triggers.mjs.
export const loadSentences = (rows, table) => {
  const errors = []
  const [header, ...body] = parseCsv(fs.readFileSync(SENTENCES, "utf-8"))
  if (SENTENCE_HEADER.some((c, i) => header[i] !== c) || header.length !== SENTENCE_HEADER.length) {
    return { sentences: [], errors: [`expected the header ${SENTENCE_HEADER.join(",")}, got ${header.join(",")}`] }
  }

  const byTrigger = new Map(rows.map(r => [r.trigger, r]))
  const infinitives = new Set(table.map(v => v.infinitive))
  const seen = new Map()
  const sentences = []

  body.filter(cells => cells.length > 1).forEach((cells, i) => {
    const line = i + 2
    if (cells.length !== SENTENCE_HEADER.length) {
      errors.push(`line ${line} has ${cells.length} fields, not ${SENTENCE_HEADER.length}`)
      return
    }
    const [trigger, verb, person, text, pair, notes] = cells
    const bank = byTrigger.get(trigger)
    if (!bank) errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(trigger)} is not a trigger in ${CSV}`)
    if (!infinitives.has(verb)) errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(verb)} is not a verb in the table`)
    if (!personNames.includes(person)) errors.push(`${SENTENCES} line ${line}: unknown person ${JSON.stringify(person)}`)
    if (!TEXT.test(text)) errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(text)} is not lowercase words separated by single spaces`)
    const parts = text.split(BLANK)
    if (parts.length !== 2) {
      errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(text)} needs exactly one ${BLANK}`)
      return
    }
    const before = parts[0], after = parts[1]
    if (!/^.*[a-zñáéíóúü] $/.test(before)) errors.push(`${SENTENCES} line ${line}: the blank needs words before it, with a space, and a subject among them`)
    if (after !== "" && !after.startsWith(" ")) errors.push(`${SENTENCES} line ${line}: the blank is a whole word`)
    if (bank && !bank.forms.some(f => f.pattern.test(before))) {
      errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(text)} does not use ${JSON.stringify(trigger)} before the blank, in one of its forms (${bank.forms.map(f => f.words).join(", ")})`)
    }
    if (seen.has(text)) errors.push(`${SENTENCES} line ${line}: ${JSON.stringify(text)} is already the sentence on line ${seen.get(text)}`)
    seen.set(text, line)
    const form = bank ? bank.forms.find(f => f.pattern.test(before)) : null
    sentences.push({ line, trigger, verb, person, text, before, after, pair, notes, bank, form })
  })

  return { sentences, errors }
}
