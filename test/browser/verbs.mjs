import fs from "fs"
import path from "path"
import { REPO, formatVersion, storageKey, wait } from "./harness.mjs"
import { parseCsv } from "../../tools/deck-source.mjs"

export const name = "The verb drills"

const VERBS = "flashcards.verbs.v1"

// Read from the CSVs the generator reads, so the suite follows the bank and
// the table rather than restating them.
const rows = file => parseCsv(fs.readFileSync(path.join(REPO, file), "utf-8")).slice(1).filter(r => r.length > 1)
const table = new Map(rows("data/es-verbs.csv").map(([inf, tense, person, form]) => [`${inf}.${tense}.${person}`, form]))
const corpus = rows("data/es-paraphrase.csv").map(
  ([id, prompt, model, verb, tense, person, trap, against]) =>
    ({ id, prompt, model, verb, tense, person, trap, against }))

// Every item the tense shift yields, so a seed can put them all behind us and
// leave the person shift at the front of the session.
const shiftSlugs = () => {
  const out = new Set()
  for (const s of bank) for (const t of ["present", "preterite", "imperfect"]) {
    if (t !== s.tense) out.add(`${s.infinitive}.${t}`)
  }
  return [...out]
}

// As the page names a person, `→ nosotros`.
const PRONOUNS = { yo: "1s", tú: "2s", él: "3s", nosotros: "1p", ellos: "3p" }

// And every item the person shift yields, for a seed that leaves the
// paraphrase prompts at the front.
const personSlugs = () => {
  const out = new Set()
  for (const s of bank.filter(s => s.personShift)) for (const p of Object.values(PRONOUNS)) {
    if (p !== s.person) out.add(`person.${s.infinitive}.${s.tense}.${p}`)
  }
  return [...out]
}

// The por / para bank, by the English it asks, which is unique to a row even
// where two rows share their Spanish.
const porPara = rows("data/es-por-para.csv").map(([text, english, item]) => {
  const [, before, answer, after] = text.match(/^(.*)\[(.*)\](.*)$/)
  return { before, answer, after, english, item, slug: `porpara.${item}`, full: before + answer + after }
})
const porParaSlugs = () => [...new Set(porPara.map(r => r.slug))]
const otherWord = w => w === "por" ? "para" : "por"

// Error correction's items are its kinds, so there are four and they are
// named rather than derived.
const errorSlugs = ["regularised", "strong-weak", "strong-imperfect", "boot"].map(k => `error.${k}`)

const bank = rows("data/es-sentences.csv").map(([text, infinitive, tense, person, personShift]) => {
  const [, before, form, after] = text.match(/^(.*)\[(.*)\](.*)$/)
  return { plain: before + form + after, before, after, infinitive, tense, person, personShift: personShift === "yes" }
})

// Where the deck ranks a verb, which is the order a verb's shifts are first
// met in (#51). The deck writes `ir(se)` where the table writes `ir`.
const deckRank = new Map(rows("data/es-1000.csv").map(([rank, , word]) => [word.replace(/\(se\)$/, ""), Number(rank)]))
const byFrequency = sentences =>
  sentences.map((s, i) => [s, i]).sort(([a, i], [b, j]) =>
    (deckRank.get(a.infinitive) ?? Infinity) - (deckRank.get(b.infinitive) ?? Infinity) || i - j).map(([s]) => s)

// What the page is asking, and what the answer to it is. A pronoun is a
// person shift and holds the tense; anything else is a tense, and holds the
// person.
const asked = async page => {
  const plain = await page.text(".verb-sentence")
  const target = (await page.text(".verb-target")).replace(/^→ /, "")
  const s = bank.find(s => s.plain === plain)
  const person = PRONOUNS[target]
  const [tense, slug] = person
    ? [s.tense, `person.${s.infinitive}.${s.tense}.${person}`]
    : [target, `${s.infinitive}.${target}`]
  const form = table.get(`${s.infinitive}.${tense}.${person ?? s.person}`)
  return { ...s, target, form, slug, full: s.before + form + s.after }
}

const answer = async (page, typed) => {
  await page.type(".verb-answer", typed)
  await page.tap(".grade")
}

const next = page => page.tap(".grade")

export default async ({ check, open, blobs }) => {
  const page = await open({ path: "/verbs", key: VERBS })
  await page.waitForSelector(".verb-sentence")
  await wait(400)

  // --- the first item is the most common verb's first sentence, moved ---
  const first = await asked(page)
  const opens = byFrequency(bank)[0]
  check("asks the most common verb's first sentence", first.plain, opens.plain)
  check("into a tense it is not in", first.target !== opens.tense, true)
  check("with the box where the verb goes",
    [await page.text(".verb-before"), await page.text(".verb-after")], [first.before, first.after])

  // --- a right answer grades GotIt ---
  await answer(page, first.form)
  check("a right answer shows the sentence moved", await page.text(".milestone"), `✓ ${first.full}`)
  check("with nothing to add, since the prompt named the tense", await page.text(".verb-note"), null)

  let stored = await page.stored()
  check("and is written under the page's own key", stored.cards.length, 1)
  check("keyed by verb and tense, not by sentence", stored.cards[0].slug, first.slug)
  check("graded as got", stored.cards[0].missed, 0)
  check("through the same codec as everything else", stored.version, formatVersion())
  check("naming its own namespace", stored.language, "verbs")

  // The whole architectural claim: one scheduler, two pages, separate
  // histories. If the flashcards moved, the pages are not separate.
  check("with the flashcards untouched", await page.stored(storageKey), null)

  // --- accents are not the thing being drilled ---
  // The session is spread so that one verb is never asked twice running
  // (#51), so the first accented form is a question or two along. Answered
  // rightly until it arrives.
  await next(page)
  let item = await asked(page)
  for (let i = 0; i < 5 && !/[áéíóú]/.test(item.form); i++) {
    await answer(page, item.form)
    await next(page)
    item = await asked(page)
  }
  check("an item comes with an accent to leave off", /[áéíóú]/.test(item.form), true)
  await answer(page, item.form.normalize("NFD").replace(/[́]/g, ""))
  check("an unaccented answer counts", await page.text(".milestone"), `✓ ${item.full}`)
  check("and the accent is shown", await page.text(".verb-accent"), `right — ${item.form}`)
  stored = await page.stored()
  check("graded as got, not missed", stored.cards.find(c => c.slug === item.slug)?.missed, 0)

  // --- a wrong answer grades Again, and comes round again ---
  await next(page)
  const missed = await asked(page)
  await answer(page, "nada")
  check("a wrong answer shows the right one", await page.text(".milestone"), `✗ ${missed.full}`)
  check("echoing back what was typed", await page.text(".verb-attempt"), "you wrote — nada")
  check("and marking the box it was typed into",
    await page.$eval(".verb-answer", e => e.className.includes("wrong")), true)
  stored = await page.stored()
  check("graded as missed", stored.cards.find(c => c.slug === missed.slug)?.missed, 1)

  // Answered rightly until the miss is asked again, which the scheduler's
  // requeue promises within the session.
  let again = null
  for (let i = 0; i < 10 && !again; i++) {
    await next(page)
    item = await asked(page)
    if (item.slug === missed.slug) again = item
    else await answer(page, item.form)
  }
  check("the missed item comes round again", again?.slug, missed.slug)
  check("asking a different sentence", again && again.plain !== missed.plain, true)

  // --- a new session is built from what was saved ---
  // Answered first, or it is still at box 0 and rightly asked first again.
  if (again) await answer(page, again.form)
  await page.evaluate(() => { location.reload() })
  await page.waitForSelector(".verb-sentence")
  await wait(400)
  stored = await page.stored()
  const reopened = await asked(page)
  check("a new session asks nothing already answered and not yet due",
    stored.cards.some(c => c.slug === reopened.slug), false)
  check("no page errors", page.errors, [])
  await page.close()

  // --- one pairing key, both pages ---
  const paired = await open({ path: "/verbs", key: VERBS })
  await paired.waitForSelector(".verb-sentence")
  await wait(500)
  const shared = await paired.evaluate(() => localStorage.getItem("flashcards.sync-key"))
  check("the pairing key is the one the flashcards use",
    /^[a-z0-9]{32}$/.test(shared ?? ""), true)
  check("and the drills are their own blob beside them",
    [...blobs.keys()].includes(`${shared}.verbs`), true)
  check("which is not the flashcards' blob",
    [...blobs.keys()].includes(`${shared}.es`), false)
  check("no page errors", paired.errors, [])
  await paired.close()

  // --- the keyboard, for a drill that is mostly typing ---
  const keys = await open({ path: "/verbs", key: VERBS })
  await keys.waitForSelector(".verb-sentence")
  await wait(400)
  const typed = await asked(keys)
  const pips = await keys.$$eval(".pip", els => els.length)
  check("a pip for every question in the session", pips, 20)
  check("none of them done yet",
    await keys.$$eval(".pip.done", els => els.length), 0)

  await keys.type(".verb-answer", typed.form)
  await keys.keyboard.press("Enter")
  await wait(150)
  check("enter checks the answer", await keys.text(".milestone"), `✓ ${typed.full}`)
  check("filling a pip", await keys.$$eval(".pip.done", els => els.length), 1)
  await keys.keyboard.press("Enter")
  await wait(150)
  // Not by the sentence: two items of the same verb draw on the same
  // sentences, so only the target moves. The cleared verdict is the proof.
  const next2 = await asked(keys)
  check("and enter again moves on", await keys.text(".milestone"), null)
  check("to the next item", next2.slug !== typed.slug, true)

  // Status, not a control: the study page's ••• opens a panel, this says
  // whether the server has it.
  // An empty box is not an answer. Enter is mapped and the box is focused from
  // the moment a question arrives, so without the guard a stray one marks the
  // item missed before it has been read.
  const untouched = await asked(keys)
  check("nothing typed, so nothing to check",
    await keys.$eval(".grade", e => e.disabled), true)
  await keys.keyboard.press("Enter")
  await wait(200)
  check("and enter does not grade it either",
    (await keys.stored())?.cards?.some(c => c.slug === untouched.slug) ?? false, false)
  // Not that the question is still up — it would be either way, with a verdict
  // under it. That there is no verdict is what tells them apart.
  check("and says nothing about an answer nobody gave",
    await keys.text(".milestone"), null)
  // A space is not an answer either. Cleared with the keyboard rather than by
  // setting `value`, which React would not hear and which would leave the
  // model holding whitespace the box no longer shows.
  await keys.type(".verb-answer", "  ")
  check("nor is whitespace", await keys.$eval(".grade", e => e.disabled), true)
  await keys.keyboard.press("Backspace")
  await keys.keyboard.press("Backspace")

  // The box is focused on arrival and again on every question, so typing can
  // start without aiming at it - and so no button is holding focus when the
  // next Enter lands.
  check("the answer box has focus to begin with",
    await keys.evaluate(() => document.activeElement?.className.includes("verb-answer")), true)

  // Tapping a button leaves it focused, and a focused button takes Enter as a
  // click. Without that being stopped this grades the next question unseen.
  const before = await asked(keys)
  // Something typed, or the button is disabled and there is no tap to test.
  await keys.type(".verb-answer", "nada")
  await keys.tap(".grade")
  await keys.keyboard.press("Enter")
  await wait(200)
  const after = await asked(keys)
  check("a tapped button does not take the next Enter as well",
    after.slug !== before.slug, true)
  check("landing one question on, not two",
    (await keys.stored()).cards.filter(c => c.seen > 0).length, 2)
  // The top bar is for the session; everything else is behind the dots, as
  // on the cards. Both are anchors: a page change is a page load here.
  check("nothing but pips and the dots in the top bar",
    await keys.$$eval(".topbar > *", es => es.map(e => e.className)), ["pips", "panel-toggle"])
  await keys.tap(".panel-toggle")
  check("the menu goes back to the cards",
    await keys.$eval("a.panel-item", e => [e.tagName, e.getAttribute("href")]), ["A", "/"])
  check("and to where pairing is",
    await keys.$$eval("a.panel-item", es => es.map(e => e.getAttribute("href"))), ["/", "/?sync"])
  // "Backed up", not "synced": a key is made on first run, so it never meant
  // that anything else shares this.
  check("saying what the server has, not who else has it",
    await keys.text(".panel-note"), "Backed up")
  await keys.dismiss()

  check("no page errors", keys.errors, [])
  await keys.close()

  // --- the person shift: the same sentences, the tense held still ---
  // The tense shift is put behind us so the session opens on the most
  // common verb's first sentence marked for a person shift, moved into the
  // first person it is not already in.
  const later = Date.now() + 30 * 86400000
  const behind = slugs => ({
    version: formatVersion(), language: "verbs", deck: "none",
    cards: slugs.map(slug =>
      ({ slug, box: 5, seen: 3, missed: 0, lapses: 0, direction: "recognition", due: later })),
  })
  const persons = await open({ path: "/verbs", key: VERBS, seed: behind(shiftSlugs()) })
  await persons.waitForSelector(".verb-sentence")
  await wait(400)

  const opening = byFrequency(bank).find(s => s.personShift)
  const moved = await asked(persons)
  check("asks the first sentence marked for it", moved.plain, opening.plain)
  check("into a person it is not in, named by a pronoun",
    PRONOUNS[moved.target] !== undefined && PRONOUNS[moved.target] !== opening.person, true)
  check("with the box where the verb goes",
    [await persons.text(".verb-before"), await persons.text(".verb-after")], [moved.before, moved.after])

  await answer(persons, moved.form)
  check("a right answer shows the sentence moved", await persons.text(".milestone"), `✓ ${moved.full}`)
  stored = await persons.stored()
  let personCard = stored.cards.find(c => c.slug === moved.slug)
  check("keyed by verb, tense and person, in its own space", moved.slug.startsWith("person."), true)
  check("graded as got", personCard?.missed, 0)
  check("and crediting no tense-shift item",
    stored.cards.filter(c => !c.slug.startsWith("person.") && c.seen !== 3).length, 0)

  await next(persons)
  const personMissed = await asked(persons)
  await answer(persons, "nada")
  check("a wrong answer shows the right one", await persons.text(".milestone"), `✗ ${personMissed.full}`)
  stored = await persons.stored()
  check("graded as missed", stored.cards.find(c => c.slug === personMissed.slug)?.missed, 1)

  // Comes round again within the session, and from a different sentence:
  // the pool is why the bank needs three persons per verb and tense.
  let personAgain = null
  for (let i = 0; i < 10 && !personAgain; i++) {
    await next(persons)
    item = await asked(persons)
    if (item.slug === personMissed.slug) personAgain = item
    else await answer(persons, item.form)
  }
  check("the missed item comes round again", personAgain?.slug, personMissed.slug)
  check("asking a different sentence", personAgain && personAgain.plain !== personMissed.plain, true)
  check("no page errors", persons.errors, [])
  await persons.close()

  // --- por / para: a preposition in the gap, the English saying which ---
  // Everything else is put behind us, so the session is the por / para items
  // and nothing else, and a miss is requeued among them.
  const pp = await open({ path: "/verbs", key: VERBS,
    seed: behind([...shiftSlugs(), ...personSlugs(), ...errorSlugs, ...corpus.map(c => `paraphrase.${c.id}`)]) })
  await pp.waitForSelector(".verb-sentence")
  await wait(400)
  const ppAsked = async () => {
    const english = await pp.text(".verb-sentence")
    return porPara.find(r => r.english === english)
  }

  const ppFirst = await ppAsked()
  check("asks the bank's first sentence, by its English", ppFirst, porPara[0])
  check("naming the choice rather than a tense", await pp.text(".verb-target"), "→ por / para")
  check("with the box where the preposition goes",
    [await pp.text(".verb-before"), await pp.text(".verb-after")], [ppFirst.before, ppFirst.after])

  await answer(pp, ppFirst.answer)
  check("a right answer shows the Spanish filled in", await pp.text(".milestone"), `✓ ${ppFirst.full}`)
  stored = await pp.stored()
  check("keyed by the contrast, not the sentence",
    stored.cards.filter(c => c.seen !== 3).map(c => [c.slug, c.missed]), [[ppFirst.slug, 0]])

  await next(pp)
  const ppMissed = await ppAsked()
  check("the next item is the next contrast", ppMissed.slug !== ppFirst.slug, true)
  await answer(pp, otherWord(ppMissed.answer))
  check("the other preposition is wrong", await pp.text(".milestone"), `✗ ${ppMissed.full}`)
  stored = await pp.stored()
  check("and graded as missed", stored.cards.find(c => c.slug === ppMissed.slug)?.missed, 1)

  let ppAgain = null
  for (let i = 0; i < 6 && !ppAgain; i++) {
    await next(pp)
    const r = await ppAsked()
    if (r.slug === ppMissed.slug) ppAgain = r
    else await answer(pp, r.answer)
  }
  check("the missed contrast comes round again", ppAgain?.slug, ppMissed.slug)
  check("asking the next sentence of its pool",
    ppAgain?.english, porPara.filter(r => r.slug === ppMissed.slug)[1].english)
  check("no page errors", pp.errors, [])
  await pp.close()
  // --- error correction: a sentence broken on purpose ---
  // The shifts and por / para are put behind us, so the session is the four
  // kinds and the paraphrase. The kinds all open on a `tener` sentence, and
  // thirteen of the sixteen paraphrase prompts are one family, ser / estar —
  // more than half the session, so it leads and goes between everything
  // else (#51). Passed, a prompt moves on by itself.
  // The sentence on screen is not in the bank - its verb is broken - so it
  // is found by the words either side of the box.
  const fixing = await open({ path: "/verbs", key: VERBS, seed: behind([...shiftSlugs(), ...personSlugs(), ...porParaSlugs()]) })
  await fixing.waitForSelector(".verb-sentence, .verb-prompt")
  await wait(400)

  const passParaphrase = async () => {
    if (await fixing.$(".verb-sentence")) return
    await fixing.tap(".grade")
    await (await fixing.byText(".grade", "Got it")).click()
    await wait(200)
  }
  await passParaphrase()

  // A subjectless sentence is shown with a pronoun in front, so the bank
  // sentence is the one whose words either side match once it is taken off.
  const broken = async () => {
    const shown = await fixing.text(".verb-sentence")
    const before = await fixing.text(".verb-before") ?? "", after = await fixing.text(".verb-after") ?? ""
    const s = bank.find(s => s.after === after &&
      (s.before === before || Object.entries(PRONOUNS).some(([p, code]) => code === s.person && `${p} ${s.before}` === before)))
    const tense = (await fixing.text(".verb-target")).replace(/^→ fix it · /, "")
    const form = table.get(`${s.infinitive}.${tense}.${s.person}`)
    return { shown, typo: shown.slice(before.length, shown.length - after.length), form, full: before + form + after }
  }

  const opening1 = await broken()
  check("asks a sentence the bank does not have", bank.some(s => s.plain === opening1.shown), false)
  check("naming the tense, and that it wants fixing", await fixing.text(".verb-target"), "→ fix it · present")
  check("broken as the first kind breaks it", opening1.shown, "yo teno mucho trabajo")
  check("with the person said, outside the box", await fixing.text(".verb-before"), "yo ")
  check("and saying nothing yet of what is wrong", await fixing.text(".verb-note"), null)
  await answer(fixing, opening1.form)
  check("a right fix shows the sentence mended", await fixing.text(".milestone"), `✓ ${opening1.full}`)
  check("and then says what the mistake was", await fixing.text(".verb-note"),
    "an irregular verb, conjugated as though it were regular")
  stored = await fixing.stored()
  check("keyed by the kind, not the verb",
    stored.cards.filter(c => c.slug.startsWith("error.")).map(c => [c.slug, c.missed]), [["error.regularised", 0]])

  // The one that forgiveness makes dangerous: typed back as shown, it must
  // be wrong. The generator refuses every error that differs from its fix
  // only by an accent, which is what makes this hold for every item.
  await next(fixing)
  await passParaphrase()
  const retyped = await broken()
  await answer(fixing, retyped.typo)
  check("the error typed back unchanged is wrong", await fixing.text(".milestone"), `✗ ${retyped.full}`)
  check("and the mistake is named then too", (await fixing.text(".verb-note")) !== null, true)
  stored = await fixing.stored()
  check("graded as missed", stored.cards.find(c => c.slug === "error.strong-weak")?.missed, 1)

  // A missing accent is still not the mistake being drilled.
  await next(fixing)
  await passParaphrase()
  const accented = await broken()
  check("the next fix has an accent to leave off", /[áéíóú]/.test(accented.form), true)
  await answer(fixing, accented.form.normalize("NFD").replace(/[́]/g, ""))
  check("and a fix without it counts", await fixing.text(".verb-accent"), `right — ${accented.form}`)

  // The missed kind comes round again, as a different sentence. Answered
  // rightly until it does; its `seen` moving to 2 is what says it was asked.
  const seenOf = async slug => (await fixing.stored()).cards.find(c => c.slug === slug)?.seen
  let fixAgain = null
  await next(fixing)
  for (let i = 0; i < 12 && !fixAgain; i++) {
    // The miss may be requeued behind a paraphrase prompt.
    if (!(await fixing.$(".verb-sentence"))) {
      await passParaphrase()
      continue
    }
    const b = await broken()
    await answer(fixing, b.form)
    if (await seenOf("error.strong-weak") === 2) fixAgain = b
    else await next(fixing)
  }
  check("the missed kind comes round again", fixAgain !== null, true)
  check("asking a different sentence", fixAgain && fixAgain.shown !== retyped.shown, true)
  check("no page errors", fixing.errors, [])
  await fixing.close()

  // --- what is next, when there is nothing now ---
  // As the cards do. Everything at box 5 and far from due, so the session is
  // empty on arrival and the page can only say when something comes back.
  const far = Date.now() + 9 * 86400000
  const settled = await open({ path: "/verbs", key: VERBS, seed: {
    version: formatVersion(), language: "verbs", deck: "none",
    cards: [...shiftSlugs(), ...personSlugs(), ...porParaSlugs(), ...errorSlugs,
            ...corpus.map(r => `paraphrase.${r.id}`)].map(slug =>
      ({ slug, box: 5, seen: 8, missed: 0, lapses: 0, direction: "recognition", due: far })),
  } })
  await settled.waitForSelector(".done-title")
  await wait(300)
  check("with nothing to do, it says when there will be",
    await settled.text(".done-stats"), "Nothing due for another 9 days.")
  check("and does not promise a review as well",
    await settled.$(".next-due"), null)
  check("no page errors", settled.errors, [])
  await settled.close()

  // --- the paraphrase, which nothing can check ---
  // The checked drills are put behind us so the session opens on the corpus;
  // every exercise type shares one queue, and the page tells them apart by
  // which `Answer` they carry rather than by which page they are on.
  const done = await open({ path: "/verbs", key: VERBS, seed: behind([...shiftSlugs(), ...personSlugs(), ...porParaSlugs(), ...errorSlugs]) })
  await done.waitForSelector(".verb-prompt")
  await wait(400)

  const opener = corpus[0]
  check("asks the corpus in its own order", await done.text(".verb-prompt"), opener.prompt)
  check("with no sentence to move", await done.text(".verb-sentence"), null)
  check("and nothing given away before the reveal", await done.text(".verb-model"), null)

  await done.tap(".grade")
  check("revealing a model answer, not the answer", await done.text(".verb-model"), opener.model)
  const lines = await done.$$eval(".verb-check", els => els.map(e => e.textContent))
  check("with the rubric that says why it is that",
    lines, [`${opener.verb}, not ${opener.against}`, opener.tense, "third person singular"])

  // Nothing compared it, so the reader says how it went.
  check("and two buttons, because nothing else can grade it",
    (await done.$$(".grade")).length, 2)

  // There is no box to hold focus here, so the tapped Reveal button still has
  // it - and a focused button takes Enter as a click, which would land on
  // Again. Enter means "check or reveal", and there is nothing left to
  // reveal, so it should do nothing at all.
  await done.keyboard.press("Enter")
  await wait(200)
  check("enter on a reveal grades nothing",
    (await done.stored())?.cards?.some(c => c.slug === `paraphrase.${opener.id}`) ?? false, false)
  check("and leaves the answer up", await done.text(".verb-model"), opener.model)
  await (await done.byText(".grade", "Got it")).click()
  await wait(200)

  stored = await done.stored()
  const graded = stored.cards.find(c => c.slug === `paraphrase.${opener.id}`)
  check("graded under the frozen id", graded?.seen, 1)
  check("as got", graded?.missed, 0)
  check("shares no item with any other drill",
    stored.cards.filter(c => !c.slug.startsWith("paraphrase.") && c.seen < 3).length, 0)
  // The corpus opens on a block of ser / estar prompts, which are one family
  // whichever verb answers them, and a session keeps one family apart
  // wherever it can (#51). So the second question is the first prompt that
  // sets another trap, and the third is the corpus's second row. Checked, so
  // that a reordered corpus fails here and not below.
  const firstTense = corpus.findIndex(r => r.trap === "tense")
  check("the corpus opens as this assumes",
    [corpus[0].trap, corpus[1].trap, firstTense > 1 && firstTense < 20], ["verb", "verb", true])
  const asked2 = [corpus[0], corpus[firstTense], corpus[1]]
  check("and moves straight on, the reveal already read",
    await done.text(".verb-prompt"), asked2[1].prompt)

  // Two taps in one tick, before the first grade can land. The typed side is
  // safe because `Answer` moves to `Compared` at once; this side has to wait
  // for the clock, so `Judging` is what stops the second.
  await done.tap(".grade")
  const twice = asked2[1]
  await done.evaluate(() => {
    const b = [...document.querySelectorAll(".grade")].find(e => e.textContent === "Got it")
    b.click(); b.click()
  })
  await wait(250)
  stored = await done.stored()
  check("a double tap grades once, not twice",
    stored.cards.filter(c => c.slug.startsWith("paraphrase.")).map(c => [c.slug, c.seen]).sort(),
    [["paraphrase." + corpus[0].id, 1], ["paraphrase." + twice.id, 1]].sort())
  check("and the next question is the next one",
    await done.text(".verb-prompt"), asked2[2].prompt)

  await done.tap(".grade")
  await (await done.byText(".grade", "Again")).click()
  await wait(200)
  stored = await done.stored()
  check("a self-graded miss is a miss",
    stored.cards.find(c => c.slug === `paraphrase.${asked2[2].id}`)?.missed, 1)
  check("no page errors", done.errors, [])
  await done.close()

  // --- the progress sheet ---
  // One of each kind slipping, one that slipped and recovered, and history
  // for an item the bank no longer yields, which must count for nothing.
  const DAY = 86400000
  const shifts = shiftSlugs(), people = personSlugs()
  const entry = (slug, box, seen, missed, lapses, dueIn) =>
    ({ slug, box, seen, missed, lapses, direction: "recognition", due: Date.now() + dueIn * DAY })
  const worked = {
    version: formatVersion(), language: "verbs", deck: "none",
    cards: [
      entry(shifts[0], 5, 6, 0, 0, 30),
      entry(shifts[1], 5, 6, 0, 0, 30),
      entry(shifts[2], 5, 6, 0, 0, 30),
      entry(shifts[3], 1, 2, 1, 0, 0.5),
      entry(shifts[4], 1, 2, 1, 0, 0.5),
      entry(shifts[5], 0, 9, 5, 4, -0.1),
      entry(people[0], 1, 7, 3, 3, 0.2),
      entry(`paraphrase.${corpus[0].id}`, 0, 12, 8, 6, -0.1),
      entry(shifts[6], 4, 10, 4, 5, 10),
      entry("gone.preterite", 0, 100, 100, 9, -1),
    ],
  }
  const openSheet = async p => {
    await p.tap(".panel-toggle")
    ;(await p.byText(".panel-item", "See your progress")).click()
    await wait(250)
  }

  const sheet = await open({ path: "/verbs", key: VERBS, seed: worked })
  await sheet.waitForSelector(".verb-sentence")
  await wait(400)
  await openSheet(sheet)
  check("the menu opens a progress sheet", await sheet.text(".sheet-title"), "Progress")
  check("and closes behind it", await sheet.$(".panel"), null)

  // 38 right of 60, leaving out the hundred answers to an item that is gone.
  const tiles = await sheet.$$eval(".tile", es => es.map(e => e.textContent))
  check("accuracy over the items the bank still yields", tiles[0], "63%correct")
  check("mastered is a count", tiles[1], "3mastered")
  check("and it says what is coming tomorrow", tiles[2], "3due tomorrow")
  check("with the raw numbers behind the percentage", await sheet.text(".tiles-note"),
    "60 answers · 22 wrong · 2 due now")

  // As the page would name each: a tense shift by verb and tense, a person
  // shift by the pronoun it asked for, a paraphrase by its English.
  const CODES = Object.fromEntries(Object.entries(PRONOUNS).map(([p, c]) => [c, p]))
  const [, pInf, pTense, pCode] = people[0].split(".")
  const listed = await sheet.$$eval(".leech", es => es.map(e =>
    [e.querySelector(".leech-label").textContent, e.querySelector(".leech-count").textContent]))
  check("what keeps slipping, worst first, each kind named as what it is", listed, [
    [corpus[0].prompt, "6"],
    [shifts[5].replace(".", " · "), "4"],
    [`${pInf} · ${pTense} · ${CODES[pCode]}`, "3"],
  ])

  // #29: the drills grow whenever a sentence is added, so a share of them
  // would fall every time the app got better. A fraction reads as *200 of
  // 1000*, numbers either side; a bare "of" would also match a paraphrase's
  // prompt, which is rendered here as its label.
  const body = await sheet.text(".sheet-body")
  check("no fraction of a total anywhere on it",
    [/\d+\s+of\s+\d+/.test(body), await sheet.$(".deck-progress"), await sheet.$(".bands")], [false, null, null])

  await sheet.tap(".sheet-close")
  check("and it closes", await sheet.$(".sheet"), null)
  check("no page errors", sheet.errors, [])
  await sheet.close()

  // Nothing answered is nothing to divide, not 0% or 100%.
  const fresh = await open({ path: "/verbs", key: VERBS })
  await fresh.waitForSelector(".verb-sentence")
  await wait(400)
  await openSheet(fresh)
  check("an untouched page claims no accuracy",
    (await fresh.$$eval(".tile", es => es.map(e => e.textContent)))[0], "—correct")
  check("says so", await fresh.text(".tiles-note"), "No answers yet.")
  check("and lists nothing as slipping", await fresh.$(".leeches"), null)
  check("no page errors", fresh.errors, [])
  await fresh.close()
}
