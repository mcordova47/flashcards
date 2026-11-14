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

  const asked = await page.text(".prompt")
  await page.tap(".panel-toggle")
  // A setting that opens the device's picker, not a toggle or a button that
  // cycles: a tap must never change the whole deck without saying to what.
  check("the panel shows the language as a setting",
    [await page.text(".setting-label"), await page.text(".setting-value")], ["Language", "Spanish"])
  check("whose picker offers both languages",
    await labels(page, ".setting-select option"), ["Spanish", "German"])
  check("and has Spanish chosen", await page.$eval(".setting-select", e => e.value), "es")
  check("opening the menu changes nothing about the card", await page.text(".prompt"), asked)
  // The select is laid invisibly over the row, so that a tap anywhere on it
  // opens the picker: a label alone does not, on a phone.
  check("and a tap anywhere along the row lands on the picker",
    await page.evaluate(() => {
      const r = document.querySelector(".setting").getBoundingClientRect()
      return [0.05, 0.5, 0.95].map(f =>
        document.elementFromPoint(r.left + r.width * f, r.top + r.height / 2).className)
    }), ["setting-select", "setting-select", "setting-select"])
  check("a Spanish accent, which cycles", await page.text(".panel-accent-name"), "Mexico")

  await page.select(".setting-select", "de")
  await wait(600)
  check("switching shows a German card", await page.text(".prompt"), "am")
  check("and says which language to answer in", await page.text(".direction"), "answer in English")

  await page.tap(".panel-toggle")
  // Locales sort by tag, so de-AT precedes de-DE, just as es-ES precedes es-MX.
  check("now offering a German accent", await page.text(".panel-accent-name"), "Germany")
  check("with a German voice picked", await page.text(".panel-voice-name"), "Anna")
  await page.tap(".panel-accent")
  await wait(300)
  check("cycling goes to the other German accent", await page.text(".panel-accent-name"), "Austria")
  check("a lone voice is named but not a control", await page.text(".panel-voice-name"), "Petra")
  check("and it previews in German, not Spanish", (await page.spoken()).at(-1).text, "richtig")
  await page.tap(".panel-accent")
  await wait(300)
  await page.dismiss()

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
  await shared.select(".setting-select", "de")
  await wait(600)
  check("switching rewrites the path", new URL(shared.url()).pathname, "/de")
  check("without stacking history entries",
    await shared.evaluate(() => history.length) < 4, true)
  check("still no page errors", shared.errors, [])
  await shared.close()

  // --- a path names a page before it names a language ---
  // `/verbs` used to strip its slashes, fail to look up as a language code,
  // fall through to the saved choice and quietly serve the flashcards. The
  // catch-all returns 200 for every path, so nothing anywhere said otherwise.
  const verbs = await open({ path: "/verbs" })
  await verbs.waitForSelector(".verb-sentence")
  await wait(400)
  check("a page that is not a language is not the flashcards",
    await verbs.text(".prompt"), null)
  check("and keeps the path it was asked for", new URL(verbs.url()).pathname, "/verbs")
  // The way back is the tab bar.
  check("reachable from the cards, and reachable back",
    await verbs.$eval("a.tab", e => e.getAttribute("href")), "/")
  check("no page errors", verbs.errors, [])
  await verbs.close()

  // A path naming nothing we have gets the address put right, rather than
  // being left claiming to be somewhere that does not exist.
  const astray = await open({ path: "/nonsense" })
  await astray.waitForSelector(".prompt")
  await wait(400)
  check("a path naming no page falls back", await astray.text(".prompt"), "yo")
  check("and says so in the address bar", new URL(astray.url()).pathname, "/es")
  await astray.close()
}
