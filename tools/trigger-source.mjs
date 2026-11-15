// The trigger frames the subjunctive is drilled with, and what a row of them
// is allowed to be. Shared by tools/sync-triggers.mjs, which generates from
// them, and tools/check-triggers.mjs, which holds them to the deck. See #230.
//
// A row is the words that come before the gap, the mood they demand, the kind
// of meaning that demands it, a reason, and optionally the row it is a minimal
// pair with:
//
//   mi madre no cree que,subjunctive,doubt,not believing it makes it a doubt...,mi madre cree que,
//
// The verb and the person are not here. They come from the conjugation table,
// so a trigger is written once and asked of every verb: `Flashcards.Verbs.Mood`
// is where the two meet, and the expected form is read from the table there.
//
// What a trigger has to be is the whole of the content rule. It takes one mood
// and only one, so the answer is decidable; and its main clause has a subject
// of its own, because with the same subject Spanish uses the infinitive and
// the gap would be a trap. Neither can be checked by a tool, which is why the
// groups are named below and a reviewer reads the Spanish.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"

export const CSV = "data/es-triggers.csv"

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

const HEADER = ["Trigger", "Mood", "Group", "Reason", "Pairs", "Notes"]
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
    const [trigger, mood, group, reason, pairs, notes] = cells
    if (!WORDS.test(trigger)) errors.push(`line ${line}: ${JSON.stringify(trigger)} is not lowercase words separated by single spaces`)
    if (!MOODS[mood]) errors.push(`line ${line}: ${JSON.stringify(mood)} is not one of ${Object.keys(MOODS).join(", ")}`)
    if (!GROUPS[group]) errors.push(`line ${line}: ${JSON.stringify(group)} is not one of ${Object.keys(GROUPS).join(", ")}`)
    else if (GROUPS[group].mood !== mood) errors.push(`line ${line}: ${group} demands the ${GROUPS[group].mood}, so ${JSON.stringify(trigger)} cannot be ${mood}`)
    if (!reason.trim()) errors.push(`line ${line}: ${JSON.stringify(trigger)} has no reason, and the reason is what is shown after the answer`)
    // The same words twice are one question, whatever else differs.
    if (seen.has(trigger)) errors.push(`line ${line}: ${JSON.stringify(trigger)} is already the trigger on line ${seen.get(trigger)}`)
    seen.set(trigger, line)
    rows.push({ line, trigger, mood, group, reason, pairs, notes })
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
