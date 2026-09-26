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
// leave the paraphrase prompts at the front of the session.
const shiftSlugs = () => {
  const out = new Set()
  for (const s of bank) for (const t of ["present", "preterite", "imperfect"]) {
    if (t !== s.tense) out.add(`${s.infinitive}.${t}`)
  }
  return [...out]
}

const bank = rows("data/es-sentences.csv").map(([text, infinitive, tense, person]) => {
  const [, before, form, after] = text.match(/^(.*)\[(.*)\](.*)$/)
  return { plain: before + form + after, before, after, infinitive, tense, person }
})

// What the page is asking, and what the answer to it is.
const asked = async page => {
  const plain = await page.text(".verb-sentence")
  const target = (await page.text(".verb-target")).replace(/^→ /, "")
  const s = bank.find(s => s.plain === plain)
  const form = table.get(`${s.infinitive}.${target}.${s.person}`)
  return { ...s, target, form, slug: `${s.infinitive}.${target}`, full: s.before + form + s.after }
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

  // --- the first item is the bank's first sentence, moved ---
  const first = await asked(page)
  check("asks the bank's first sentence", first.plain, bank[0].plain)
  check("into a tense it is not in", first.target !== bank[0].tense, true)
  check("with the box where the verb goes",
    [await page.text(".verb-before"), await page.text(".verb-after")], [first.before, first.after])

  // --- a right answer grades GotIt ---
  await answer(page, first.form)
  check("a right answer shows the sentence moved", await page.text(".milestone"), `✓ ${first.full}`)

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
  await next(page)
  let item = await asked(page)
  check("the next item has an accent to leave off", /[áéíóú]/.test(item.form), true)
  await answer(page, item.form.normalize("NFD").replace(/[́]/g, ""))
  check("an unaccented answer counts", await page.text(".milestone"), `✓ ${item.full}`)
  check("and the accent is shown", await page.text(".verb-accent"), `right — ${item.form}`)
  stored = await page.stored()
  check("graded as got, not missed", stored.cards.find(c => c.slug === item.slug)?.missed, 0)

  // --- a wrong answer grades Again, and comes round again ---
  await next(page)
  const missed = await asked(page)
  await answer(page, "nada")
  check("a wrong answer shows the right one", await page.text(".milestone"), missed.full)
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

  // --- the paraphrase, which nothing can check ---
  // The shift items are put behind us so the session opens on the corpus;
  // both exercise types share one queue, and the page tells them apart by
  // which `Answer` they carry rather than by which page they are on.
  const later = Date.now() + 30 * 86400000
  const done = await open({ path: "/verbs", key: VERBS, seed: {
    version: formatVersion(), language: "verbs", deck: "none",
    cards: shiftSlugs().map(slug =>
      ({ slug, box: 5, seen: 3, missed: 0, lapses: 0, direction: "recognition", due: later })),
  } })
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
  await (await done.byText(".grade", "Got it")).click()
  await wait(200)

  stored = await done.stored()
  const graded = stored.cards.find(c => c.slug === `paraphrase.${opener.id}`)
  check("graded under the frozen id", graded?.seen, 1)
  check("as got", graded?.missed, 0)
  check("shares no item with the tense shift",
    stored.cards.filter(c => !c.slug.startsWith("paraphrase.") && c.seen < 3).length, 0)
  check("and moves straight on, the reveal already read",
    await done.text(".verb-prompt"), corpus[1].prompt)

  // Two taps in one tick, before the first grade can land. The typed side is
  // safe because `Answer` moves to `Compared` at once; this side has to wait
  // for the clock, so `Judging` is what stops the second.
  await done.tap(".grade")
  const twice = corpus[1]
  await done.evaluate(() => {
    const b = [...document.querySelectorAll(".grade")].find(e => e.textContent === "Got it")
    b.click(); b.click()
  })
  await wait(250)
  stored = await done.stored()
  check("a double tap grades once, not twice",
    stored.cards.filter(c => c.slug.startsWith("paraphrase.")).map(c => [c.slug, c.seen]),
    [["paraphrase." + corpus[0].id, 1], ["paraphrase." + twice.id, 1]])
  check("and the next question is the next one",
    await done.text(".verb-prompt"), corpus[2].prompt)

  await done.tap(".grade")
  await (await done.byText(".grade", "Again")).click()
  await wait(200)
  stored = await done.stored()
  check("a self-graded miss is a miss",
    stored.cards.find(c => c.slug === `paraphrase.${corpus[2].id}`)?.missed, 1)
  check("no page errors", done.errors, [])
  await done.close()
}
