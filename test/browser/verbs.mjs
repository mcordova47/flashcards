import { storageKey, wait } from "./harness.mjs"

export const name = "The verb drills"

const VERBS = "flashcards.verbs.v1"

export default async ({ check, open, blobs }) => {
  const page = await open({ path: "/verbs", key: VERBS })
  await page.waitForSelector(".prompt")
  await wait(400)

  check("the page is its own, not the flashcards", await page.text(".prompt"), "ser · preterite · yo")

  // --- an answer is checked, not self-graded ---
  await page.type(".verb-answer", "fui")
  await page.tap(".grade")
  check("a right answer says so", await page.text(".milestone"), "Right.")

  const stored = await page.stored()
  check("and is written under the page's own key", stored.cards.length, 1)
  check("keyed by what the scheduler schedules", stored.cards[0].slug, "ser.preterite")
  check("through the same codec as everything else", stored.version, 5)
  check("naming its own namespace", stored.language, "verbs")

  // The whole architectural claim: one scheduler, two pages, separate
  // histories. If the flashcards moved, the pages are not separate.
  check("with the flashcards untouched", await page.stored(storageKey), null)

  // --- a wrong answer, and the accent rule ---
  await page.tap(".grade")
  await page.evaluate(() => { location.reload() })
  await page.waitForSelector(".prompt")
  await wait(400)
  await page.type(".verb-answer", "tuve")
  await page.tap(".grade")
  check("a wrong answer shows the right one", await page.text(".milestone"), "fui")

  await page.close()

  // --- accents are not the thing being drilled ---
  const accents = await open({ path: "/verbs", key: VERBS })
  await accents.waitForSelector(".prompt")
  await wait(400)
  // `fui` has none, so prove the rule on a form that does: `Exercise.matches`
  // is specced for that. Here it is enough that an exact answer still counts
  // after the round trip through the DOM.
  await accents.type(".verb-answer", "  FUI. ")
  await accents.tap(".grade")
  check("case, space and a full stop are not the exercise",
    await accents.text(".milestone"), "Right.")
  await accents.close()

  // --- one pairing key, both pages ---
  const paired = await open({ path: "/verbs", key: VERBS })
  await paired.waitForSelector(".prompt")
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
