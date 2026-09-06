import { speechStub, wait } from "./harness.mjs"

export const name = "Switching language"

// A device with voices for both languages, and an English one to be ignored.
const VOICES = [
  { name: "Mónica", lang: "es-ES" },
  { name: "Paulina", lang: "es-MX" },
  { name: "Anna", lang: "de-DE" },
  { name: "Markus", lang: "de-DE" },
  { name: "Petra", lang: "de-AT" },
  { name: "Samantha", lang: "en-US" },
]

const labels = (page, sel) => page.$$eval(sel, bs => bs.map(b => b.textContent))

export default async ({ check, open }) => {
  const page = await open({ stub: speechStub(VOICES) })
  await page.waitForSelector(".prompt")
  await wait(500)
  check("opens on Spanish", await page.text(".prompt"), "yo")
  await page.tap(".card")
  await page.tap(".got-it")
  check("studied one Spanish card", (await page.stored()).cards.length, 1)

  await page.tap(".panel-toggle")
  const langs = await labels(page, ".lang")
  check("the panel offers both languages", langs, ["Spanish", "German"])
  check("Spanish accents only", await labels(page, ".accent"), ["Spain", "Mexico"])

  ;(await page.byText(".lang", "German")).click()
  await wait(600)
  check("switching shows a German card", await page.text(".prompt"), "am")
  check("and says which language to answer in", await page.text(".direction"), "answer in English")

  await page.tap(".panel-toggle")
  // Locales sort by tag, so de-AT precedes de-DE, just as es-ES precedes es-MX.
  check("now offering German accents", await labels(page, ".accent"), ["Austria", "Germany"])
  check("with a German voice picked", await page.text(".panel-voice-name"), "Anna")
  ;(await page.byText(".accent", "Austria")).click()
  await wait(300)
  check("a lone voice is named but not a control", await page.text(".panel-voice-name"), "Petra")
  check("and it previews in German, not Spanish", (await page.spoken()).at(-1).text, "richtig")
  ;(await page.byText(".accent", "Germany")).click()
  await wait(300)
  await page.tap(".backdrop")

  check("no example before the flip - most contain the word", await page.$(".example"), null)
  await page.tap(".card")
  check("the German card shows its example sentence",
    await page.text(".example"), "Wir treffen uns am Dienstag.")
  await page.tap(".got-it")
  const de = await page.evaluate(() => JSON.parse(localStorage.getItem("flashcards.de.v1")))
  const es = await page.evaluate(() => JSON.parse(localStorage.getItem("flashcards.es.v1")))
  check("German progress lands in its own key", de.cards.length, 1)
  check("Spanish progress is untouched", es.cards.length, 1)
  check("the two decks have different fingerprints", de.deck !== es.deck, true)
  check("the choice is remembered", await page.evaluate(() => localStorage.getItem("flashcards.language")), "de")

  // Let the forked saves finish; reloading on top of them detaches the frame.
  await wait(200)
  await page.reload({ waitUntil: "domcontentloaded" })
  await page.waitForSelector(".prompt")
  await wait(400)
  check("and survives a reload", await page.text(".prompt"), "der Artikel")
  check("no page errors", page.errors, [])
  await page.close()

  // A shared link opens what it says, whatever the reader was last studying.
  const shared = await open({ stub: speechStub(VOICES), path: "/de" })
  await shared.evaluate(() => localStorage.setItem("flashcards.language", "es"))
  await shared.reload({ waitUntil: "networkidle0" })
  await shared.waitForSelector(".prompt")
  await wait(400)
  check("a /de link opens German over a saved Spanish choice", await shared.text(".prompt"), "am")

  // The root defers to the reader instead, so the installed app reopens where
  // they left off.
  await shared.evaluate(() => localStorage.setItem("flashcards.language", "es"))
  await shared.goto(shared.url().replace(/\/de$/, "/"), { waitUntil: "networkidle0" })
  await shared.waitForSelector(".prompt")
  await wait(400)
  check("the root defers to their own choice", await shared.text(".prompt"), "yo")

  // Switching makes the address bar copyable.
  await shared.tap(".panel-toggle")
  ;(await shared.byText(".lang", "German")).click()
  await wait(600)
  check("switching rewrites the path", new URL(shared.url()).pathname, "/de")
  check("without stacking history entries",
    await shared.evaluate(() => history.length) < 4, true)
  check("still no page errors", shared.errors, [])
  await shared.close()
}
