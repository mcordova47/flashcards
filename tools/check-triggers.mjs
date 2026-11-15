// Checks the trigger sentences. See #230 and #241.
//
//   node tools/check-triggers.mjs          check
//   node tools/check-triggers.mjs --show   check, then print every sentence
//                                          with its answer, for reading
//
// Holds every word of a sentence to the deck's vocabulary, as check-sentences
// and check-por-para hold theirs: a deck word, a regular inflection of one, or
// named in the Notes of the sentence or of its trigger. A sentence is there to
// ask about a mood, and a word the learner has not met is a second question.
//
// Holds each sentence to the conjugation table. The answer is never in the
// data, so what can be wrong is the *blank*: that its subject is the person
// the row says (so that the table's cell is the right one), that the verb is
// not already said in the main clause (`mi madre quiere que yo quiera`), that
// the main clause has a subject of its own (the same subject takes the
// infinitive, which would make the blank a trap), and that an indicative
// trigger is not a negated one (`no cree que` is the doubt, and is filed
// there). And that, for every cell, the subjunctive differs from the present,
// so the form typed says which mood was chosen.
//
// Holds a minimal pair to being one: the same sentence with only the trigger's
// `no` and the mood changed.
//
// And holds the banks to the shape that makes them teach a pattern and not a
// list of phrases: every kind of meaning has at least three triggers, indicative
// ones are at least a quarter of both the triggers and the sentences, no
// trigger is more than a sixth of the sentences, every verb and person has
// enough sentences to turn through, and there are minimal pairs.
//
// Whether a sentence is natural Mexican Spanish and means something, no tool
// can say. That is the reviewer's, and the native-speaker list (#132).

import { PERSONS, loadTable } from "./verb-source.mjs"
import { CSV, GROUPS, MIN_CELL, MIN_INDICATIVE_SHARE, MIN_PAIRS, MIN_PER_GROUP, MAX_TRIGGER_SHARE, SENTENCES, loadRows, loadSentences } from "./trigger-source.mjs"
import { knownWords, unexplained, words } from "./deck-vocabulary.mjs"

const { verbs, errors: tableErrors } = loadTable()
const { rows, errors } = loadRows()
const { sentences, errors: sentenceErrors } = loadSentences(rows, verbs)
for (const e of [...tableErrors, ...errors, ...sentenceErrors]) console.error(`x ${e}`)
if (tableErrors.length || errors.length || sentenceErrors.length) process.exit(1)

const known = knownWords(verbs)
let wrong = 0
for (const r of rows) {
  // The trigger and every form it may take in a sentence.
  for (const word of unexplained(known, [r.trigger, ...r.forms.map(f => f.words.replace(/\*/g, ""))].join(" "), r.notes)) {
    wrong++
    console.error(`x line ${r.line} (${r.trigger}): ${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }
}

console.log(`${rows.length} triggers in ${Object.keys(GROUPS).length} groups:`)
for (const [group, { mood, label }] of Object.entries(GROUPS)) {
  const n = rows.filter(r => r.group === group).length
  console.log(`  ${group.padEnd(14)} ${String(n).padStart(2)}  ${mood.padEnd(12)} ${label}`)
  if (n < MIN_PER_GROUP) {
    wrong++
    console.error(`x ${group} has ${n} trigger(s); a kind of meaning needs at least ${MIN_PER_GROUP}, or it is learned as a phrase`)
  }
}

const indicative = rows.filter(r => r.mood === "indicative").length
const share = indicative / rows.length
console.log(`  indicative: ${indicative} of ${rows.length} (${Math.round(share * 100)}%)`)
if (share < MIN_INDICATIVE_SHARE) {
  wrong++
  console.error(`x ${indicative} of ${rows.length} triggers are indicative; at least ${MIN_INDICATIVE_SHARE * 100}% are needed, or typing the subjunctive always wins`)
}

// A trigger that is another with `no` put in is a minimal pair, and the only
// kind worth having: say so, or the pairing is an accident of the file order.
const byTrigger = new Map(rows.map(r => [r.trigger, r]))
for (const r of rows) {
  const base = r.trigger.replace(/ no /, " ").replace(/^no /, "")
  if (base !== r.trigger && byTrigger.has(base) && r.pairs !== base) {
    wrong++
    console.error(`x line ${r.line} (${r.trigger}) is the negation of ${JSON.stringify(base)}, which is a trigger: mark them as a pair`)
  }
}
const pairs = rows.filter(r => r.pairs && r.mood === "subjunctive").length
console.log(`  minimal pairs: ${pairs}`)
if (pairs < 2) {
  wrong++
  console.error(`x ${pairs} minimal pair(s); the bank needs at least two, since only the doubt differs in a pair and that teaches the rule`)
}

// The premise of the whole drill: the form typed shows which mood was chosen.
// The expected form is always a cell of the table (the exercise is made from
// it, `Flashcards.Verbs.Mood.exercise`), and it is only a decision if the
// subjunctive cell is not the present one. Accents are forgiven in grading, so
// they must differ without them too. Held for every cell of the table, which
// is more than the bank wires, so that adding a verb needs no new proof.
const bare = form => form.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
let cells = 0, apart = 0
for (const verb of verbs) {
  for (const person of PERSONS.map(p => p.name)) {
    const present = verb.cells.get(`present.${person}`), subjunctive = verb.cells.get(`subjunctive.${person}`)
    cells++
    if (bare(present) === bare(subjunctive)) {
      wrong++
      console.error(`x ${verb.infinitive} ${person}: the subjunctive ${subjunctive} is the present ${present}, so the form typed would not say which mood was chosen`)
    } else apart++
  }
}
console.log(`  subjunctive differs from present, accents or not, in ${apart} of ${cells} cells`)

// ---- the sentences ----

const byName = new Map(verbs.map(v => [v.infinitive, v]))
const PRONOUNS = {
  yo: "1s", "tú": "2s", "él": "3s", ella: "3s", usted: "3s",
  nosotros: "1p", nosotras: "1p", ellos: "3p", ellas: "3p", ustedes: "3p",
}
// Said between the subject and the verb without being the subject.
const BETWEEN = new Set(["no", "ya", "siempre", "nunca", "también", "me", "te", "se", "nos", "lo", "la", "le", "les", "los", "las"])
// Nouns that end in s and are singular.
const SINGULAR_S = new Set(["mes", "país", "lunes", "martes", "miércoles", "jueves", "viernes", "dios", "inglés", "crisis", "paraguas"])

// The person of the subject the blank follows, read off the words before it:
// a pronoun says it, and `x y yo` is `nosotros`; a noun is third person, plural
// if it ends in s. `null` when there is no subject to read, which the caller
// refuses: a blank has to have its subject in front of it.
const subjectOf = before => {
  const ws = words(before)
  while (ws.length && BETWEEN.has(ws[ws.length - 1])) ws.pop()
  const last = ws[ws.length - 1], prev = ws[ws.length - 2]
  if (!last) return null
  const pronoun = PRONOUNS[last]
  if (pronoun) {
    if (prev === "y") return last === "yo" || ws[ws.length - 3] === "yo" ? "1p" : "3p"
    return { person: pronoun, pronoun: true }
  }
  return { person: !SINGULAR_S.has(last) && last.endsWith("s") ? "3p" : "3s", pronoun: false }
}

const check = (s, message) => {
  wrong++
  console.error(`x ${SENTENCES} line ${s.line} (${s.text}): ${message}`)
}

const answerOf = s => {
  const tense = s.bank.mood === "subjunctive" ? "subjunctive" : "present"
  return byName.get(s.verb).cells.get(`${tense}.${s.person}`)
}

for (const s of sentences) {
  // The words around the blank are deck words, or named. The form in the
  // blank is the table's, and the table's forms are known words.
  for (const word of unexplained(known, s.before + s.after, `${s.notes} ${s.bank.notes}`)) {
    check(s, `${word} is not a deck word or a regular inflection of one; say why in Notes`)
  }

  // The blank is the person the row says, so that the cell read from the
  // table is the right one.
  let subject = subjectOf(s.before)
  if (subject === null) check(s, "no subject before the blank to say whose verb it is")
  else {
    if (typeof subject === "string") subject = { person: subject, pronoun: true }
    if (subject.person !== s.person) check(s, `the blank follows a ${subject.person} subject but the row says ${s.person}, so the table's cell would be the wrong one`)

    // The main clause has a subject of its own. The form carries the person
    // of its subject (`quiero que/1s`), and the same subject takes the
    // infinitive. A pronoun for the same third person is the same person.
    const main = s.form.person
    if (main && main === subject.person && (main[0] !== "3" || subject.pronoun)) {
      check(s, `the main clause (${s.form.words}) and the blank are both ${main}; with the same subject Spanish uses the infinitive`)
    }
  }

  // `mi madre quiere que yo quiera`: the verb said twice, in the trigger or
  // anywhere before the blank. The `ir a` that makes a future (`va a pedir
  // que`) is not the verb `ir` being said, so it is left out of the trigger.
  // Not `ser`, which the impersonal triggers (`es importante que`) say as a
  // matter of course.
  const matchEnd = s.before.search(s.form.pattern)
  if (s.verb !== "ser") {
    const matched = s.before.match(s.form.pattern)[0]
    const outside = s.before.replace(matched, matched.replace(/\b(voy|vas|va|vamos|van) a\b/, " "))
    const verb = byName.get(s.verb)
    const said = words(outside).find(w => [...verb.cells.values()].includes(w))
    if (said) check(s, `${said} is a form of ${s.verb}, the verb in the blank; the same verb twice reads as a stutter`)
  }

  // `no cree que` is the doubt, and belongs to it. An indicative trigger
  // that is negated is a different trigger that takes the other mood.
  if (s.bank.mood === "indicative" && /\bno $/.test(s.before.slice(0, matchEnd))) {
    check(s, `${s.trigger} is negated (no), which is the doubt trigger and takes the subjunctive`)
  }
}

// Minimal pairs: the same sentence with only the doubt changed.
const pairIds = new Map()
for (const s of sentences.filter(s => s.pair)) {
  if (!pairIds.has(s.pair)) pairIds.set(s.pair, [])
  pairIds.get(s.pair).push(s)
}
let pairCount = 0
for (const [id, members] of pairIds) {
  if (members.length !== 2) { wrong++; console.error(`x pair ${id} has ${members.length} sentence(s), and a pair has two`); continue }
  const sub = members.find(m => m.bank.mood === "subjunctive"), ind = members.find(m => m.bank.mood === "indicative")
  if (!sub || !ind) { wrong++; console.error(`x pair ${id} is not one subjunctive and one indicative sentence`); continue }
  if (sub.bank.pairs !== ind.trigger) check(sub, `${sub.trigger} is not marked in ${CSV} as the pair of ${ind.trigger}`)
  if (sub.verb !== ind.verb || sub.person !== ind.person) check(sub, `pair ${id} is not the same verb and person on both sides`)
  const negated = sub.form.words, plain = ind.form.words
  // The same words but the `no`, and nothing else.
  const rebuilt = sub.text.replace(sub.form.pattern, plain)
  if (rebuilt !== ind.text) check(sub, `pair ${id}: removing the no gives ${JSON.stringify(rebuilt)}, not ${JSON.stringify(ind.text)}; a minimal pair differs in the doubt only`)
  pairCount++
}

// ---- the balance ----

const indicativeSentences = sentences.filter(s => s.bank.mood === "indicative")
const sentenceShare = indicativeSentences.length / sentences.length
console.log(`${sentences.length} sentences, ${indicativeSentences.length} indicative (${Math.round(sentenceShare * 100)}%), ${pairCount} minimal pairs`)
if (sentenceShare < MIN_INDICATIVE_SHARE - 1e-9) {
  wrong++
  console.error(`x ${indicativeSentences.length} of ${sentences.length} sentences are indicative; at least ${MIN_INDICATIVE_SHARE * 100}% are needed, or typing the subjunctive always wins`)
}
if (pairCount < MIN_PAIRS) {
  wrong++
  console.error(`x ${pairCount} minimal pair(s); at least ${MIN_PAIRS} are needed, since only the doubt differs in a pair and that teaches the rule`)
}

console.log("  by group:")
for (const [group, { label }] of Object.entries(GROUPS)) {
  const n = sentences.filter(s => s.bank.group === group).length
  console.log(`    ${group.padEnd(14)} ${String(n).padStart(3)}  ${label}`)
  if (n === 0) { wrong++; console.error(`x no sentence for ${group}`) }
}

// Not one phrase carrying the bank.
console.log("  by trigger:")
for (const r of rows) {
  const n = sentences.filter(s => s.trigger === r.trigger).length
  console.log(`    ${r.trigger.padEnd(18)} ${String(n).padStart(3)}`)
  if (n === 0) { wrong++; console.error(`x ${r.trigger} has no sentence`) }
  if (n / sentences.length > MAX_TRIGGER_SHARE) {
    wrong++
    console.error(`x ${r.trigger} is ${n} of ${sentences.length} sentences; no trigger may be more than ${Math.round(MAX_TRIGGER_SHARE * 100)}%, or it is learned as a phrase`)
  }
}

// Every verb and person has enough to turn through, with an indicative one.
const cellsAsked = new Map()
for (const s of sentences) {
  const key = `${s.verb}.${s.person}`
  if (!cellsAsked.has(key)) cellsAsked.set(key, [])
  cellsAsked.get(key).push(s)
}
const verbsAsked = [...new Set(sentences.map(s => s.verb))]
const sizes = []
for (const verb of verbsAsked) for (const { name: person } of PERSONS) {
  const here = cellsAsked.get(`${verb}.${person}`) ?? []
  sizes.push(here.length)
  if (here.length < MIN_CELL) { wrong++; console.error(`x ${verb} ${person} has ${here.length} sentence(s); at least ${MIN_CELL} are needed to turn through`) }
  if (!here.some(s => s.bank.mood === "indicative")) { wrong++; console.error(`x ${verb} ${person} has no indicative sentence`) }
  if (!here.some(s => s.bank.mood === "subjunctive")) { wrong++; console.error(`x ${verb} ${person} has no subjunctive sentence`) }
  if (new Set(here.map(s => s.bank.group)).size < Math.min(here.length, 3)) { wrong++; console.error(`x ${verb} ${person}: its sentences are of too few kinds of meaning`) }
}
console.log(`  ${verbsAsked.length} verbs x ${PERSONS.length} persons, ${Math.min(...sizes)} to ${Math.max(...sizes)} sentences each`)

if (process.argv.includes("--show")) {
  for (const s of sentences) {
    console.log(`${s.verb.padEnd(7)} ${s.person} ${s.bank.group.padEnd(12)} ${s.before}${answerOf(s)}${s.after}`)
  }
}

if (wrong) {
  console.error(`${wrong} problem(s) in ${CSV} or ${SENTENCES}`)
  process.exit(1)
}
