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
}
