// The conjugation table, what a row of it is allowed to be, and what a regular
// verb would have put in it. Shared by tools/check-verbs.mjs, which proves the
// table, and tools/sync-verbs.mjs, which generates from it.

import fs from "fs"
import { parseCsv } from "./deck-source.mjs"

export const CSV = "data/es-verbs.csv"

// In table order, and with the constructor each generates to. The order is
// the order the CSV is required to be in, so the file reads as a set of
// conjugation charts and a moved row shows up as a moved row.
export const TENSES = [
  { name: "present", constructor: "Present" },
  { name: "preterite", constructor: "Preterite" },
  { name: "imperfect", constructor: "Imperfect" },
  { name: "subjunctive", constructor: "Subjunctive" },
]

// No vosotros: the deck prefers es-MX. See #12.
export const PERSONS = [
  { name: "1s", constructor: "Sg1" },
  { name: "2s", constructor: "Sg2" },
  { name: "3s", constructor: "Sg3" },
  { name: "1p", constructor: "Pl1" },
  { name: "3p", constructor: "Pl3" },
]

const HEADER = ["Infinitive", "Tense", "Person", "Form"]
const LETTERS = /^[a-zñáéíóúü]+$/

// Reads the table and refuses anything structurally wrong: a gap, a
// duplicate, a tense or person that is not one, a cell out of order. Returns
// the verbs in table order, each with its cells keyed `tense.person`.
//
// Whether a *form* is right is not decided here - that is what the regular
// comparison in check-verbs is for.
export const loadTable = () => {
  const errors = []
  const [header, ...body] = parseCsv(fs.readFileSync(CSV, "utf-8"))
  if (HEADER.some((c, i) => header[i] !== c) || header.length !== HEADER.length) {
    return { verbs: [], errors: [`expected the header ${HEADER.join(",")}, got ${header.join(",")}`] }
  }

  const tenses = TENSES.map(t => t.name), persons = PERSONS.map(p => p.name)
  const verbs = []
  const byName = new Map()

  body.forEach((cells, i) => {
    const line = i + 2
    if (cells.length !== HEADER.length) {
      errors.push(`line ${line} has ${cells.length} fields, not ${HEADER.length}`)
      return
    }
    // Exactly as written. A stray space is a mistake in the table, not
    // something to tidy away, and neither is a capital letter.
    const [infinitive, tense, person, form] = cells
    if (!LETTERS.test(infinitive)) errors.push(`line ${line}: ${JSON.stringify(infinitive)} is not an infinitive`)
    if (!tenses.includes(tense)) errors.push(`line ${line}: unknown tense ${JSON.stringify(tense)}`)
    if (!persons.includes(person)) errors.push(`line ${line}: unknown person ${JSON.stringify(person)}`)
    if (!LETTERS.test(form)) errors.push(`line ${line}: ${JSON.stringify(form)} is not a single lowercase word`)

    let verb = byName.get(infinitive)
    if (!verb) {
      verb = { infinitive, cells: new Map(), line }
      byName.set(infinitive, verb)
      verbs.push(verb)
    } else if (verbs[verbs.length - 1] !== verb) {
      errors.push(`line ${line}: ${infinitive} appears again after other verbs; keep a verb's rows together`)
    }

    const key = `${tense}.${person}`
    if (verb.cells.has(key)) {
      errors.push(`line ${line}: ${infinitive} ${tense} ${person} is already given as ${verb.cells.get(key)}`)
    }
    const expected = tenses.flatMap(t => persons.map(p => `${t}.${p}`))[verb.cells.size]
    if (expected && key !== expected && !verb.cells.has(key)) {
      errors.push(`line ${line}: ${infinitive} ${tense} ${person} is out of order; expected ${expected.replace(".", " ")}`)
    }
    verb.cells.set(key, form)
  })

  for (const verb of verbs) {
    const missing = tenses.flatMap(t => persons.map(p => `${t}.${p}`)).filter(k => !verb.cells.has(k))
    if (missing.length) {
      errors.push(`${verb.infinitive} has no ${missing.map(k => k.replace(".", " ")).join(", ")}`)
    }
  }

  return { verbs, errors }
}

// Present, preterite, imperfect and present subjunctive, by person, for each
// class. The subjunctive is built on the infinitive's stem rather than on the
// yo form, so `tenga` is reported: the rule that derives it is the thing a
// learner has to know.
export const ENDINGS = {
  ar: {
    present: ["o", "as", "a", "amos", "an"],
    preterite: ["é", "aste", "ó", "amos", "aron"],
    imperfect: ["aba", "abas", "aba", "ábamos", "aban"],
    subjunctive: ["e", "es", "e", "emos", "en"],
  },
  er: {
    present: ["o", "es", "e", "emos", "en"],
    preterite: ["í", "iste", "ió", "imos", "ieron"],
    imperfect: ["ía", "ías", "ía", "íamos", "ían"],
    subjunctive: ["a", "as", "a", "amos", "an"],
  },
  ir: {
    present: ["o", "es", "e", "imos", "en"],
    preterite: ["í", "iste", "ió", "imos", "ieron"],
    imperfect: ["ía", "ías", "ía", "íamos", "ían"],
    subjunctive: ["a", "as", "a", "amos", "an"],
  },
}

const STRONG = "aeoáéó"
const ACCENTED = "áéíóú"
const PLAIN = { á: "a", é: "e", í: "i", ó: "o", ú: "u" }

// Syllables, as far as a written accent cares. Adjacent vowels share a
// syllable unless both are strong (a, e, o) or the weak one carries the
// accent - so `vió` is one syllable, which is the whole reason the 2010 rules
// write it `vio`, while `oí` is two.
const syllables = word => {
  let count = 0, previous = null
  for (const c of word) {
    if (!"aeiouáéíóúü".includes(c)) { previous = null; continue }
    const hiatus = previous !== null
      && ((STRONG.includes(previous) && STRONG.includes(c))
          || "íú".includes(previous) || "íú".includes(c))
    if (previous === null || hiatus) count++
    previous = c
  }
  return count
}

// A monosyllable takes no written accent (vio, dio, fue, vi), except for the
// diacritic ones that tell two words apart - and those are exactly what should
// show up as deviations, since `dé` is not the regular `de`.
const orthography = word =>
  syllables(word) === 1 ? [...word].map(c => PLAIN[c] ?? c).join("") : word

export const regular = (infinitive, tense, person) => {
  // `oír` and `reír` are -ir verbs whose infinitive carries a hiatus accent.
  const cls = infinitive.slice(-2).replace("í", "i")
  const stem = infinitive.slice(0, -2)
  const endings = ENDINGS[cls]
  if (!endings) return null
  return orthography(stem + endings[tense][PERSONS.findIndex(p => p.name === person)])
}
