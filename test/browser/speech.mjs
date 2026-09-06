import { VOICES, speechStub, wait } from "./harness.mjs"

export const name = "Pronunciation, accent and voice"

// Speaking goes through a fork and a voice-list check, so it lands a little
// after the click. Wait for the utterance rather than guessing at a delay.
const spokenAtLeast = async (page, n) => {
  for (let i = 0; i < 40; i++) {
    if ((await page.spoken()).length >= n) return
    await wait(50)
  }
}

export default async ({ check, open }) => {
  const page = await open({ stub: speechStub() })
  await page.waitForSelector(".prompt")
  await wait(450)

  check("no speaker before the flip — it would give the answer away", await page.$(".speak"), null)
  await page.tap(".card")
  check("the speaker appears with the answer", !!(await page.$(".speak")), true)

  await page.tap(".speak")
  await spokenAtLeast(page, 1)
  const said = (await page.spoken()).at(-1)
  check("it says the Spanish, not the English", said.text, "yo")
  check("in the default accent", said.lang, "es-MX")
  check("choosing the real voice over the novelty ones", said.voice, "Paulina")
  check("a shade slower than natural", said.rate, 0.9)
  check("and does not cancel when nothing is speaking",
    await page.evaluate(() => window.__cancels), 0)

  await page.keyboard.press("s")
  await spokenAtLeast(page, 2)
  check("the s key speaks too", (await page.spoken()).length, 2)
  check("interrupting an utterance in flight", await page.evaluate(() => window.__cancels), 1)

  await page.tap(".panel-toggle")
  check("one option per locale, not per voice",
    await page.$$eval(".accent", es => es.map(e => e.textContent)), ["Spain", "Mexico"])
  check("Mexican by default",
    await page.$$eval(".accent.chosen", es => es.map(e => e.textContent)), ["Mexico"])
  check("the voice row shows the automatic pick", await page.text(".panel-voice-name"), "Paulina")

  await page.tap(".panel-voice")
  check("cycling moves off a pick that may not work",
    await page.text(".panel-voice-name"), "Rocko (Spanish (Mexico))")
  await spokenAtLeast(page, 3)
  check("previewing it with the word that shows the difference",
    (await page.spoken()).at(-1), { text: "gracias", lang: "es-MX", rate: 0.9, voice: "Rocko (Spanish (Mexico))" })
  await page.tap(".panel-voice")
  check("and keeps going", await page.text(".panel-voice-name"), "Eddy (Spanish (Mexico))")
  await page.tap(".panel-voice")
  check("wrapping around", await page.text(".panel-voice-name"), "Paulina")

  ;(await page.byText(".accent", "Spain")).click()
  await wait(150)
  check("switching accent repicks that accent's voice", await page.text(".panel-voice-name"), "Mónica")
  check("and persists the choice",
    await page.evaluate(() => localStorage.getItem("flashcards.es.accent")), "es-ES")
  check("the accent stays out of the progress blob",
    Object.keys(await page.stored() ?? {}).sort(), [])

  await page.tap(".backdrop")
  await page.tap(".card")
  await page.tap(".speak")
  await spokenAtLeast(page, 5)
  check("cards speak in the chosen voice", (await page.spoken()).at(-1).voice, "Mónica")
  // This suite had no error assertion, so a thrown exception was invisible.
  check("no page errors", page.errors, [])
  await page.close()

  // A device that speaks only one Spanish has nothing to choose between.
  const solo = await open({ stub: speechStub([{ name: "Mónica", lang: "es-ES" }]) })
  await solo.waitForSelector(".prompt")
  await wait(450)
  await solo.tap(".panel-toggle")
  check("no accent picker when there is one locale", (await solo.$$(".accent")).length, 0)
  check("and no voice row when there is one voice", await solo.$(".panel-voice"), null)
  check("but the panel still works", !!(await solo.$(".panel-item")), true)
  await solo.close()

  // The invariant that matters: never hand the engine no voice at all, or it
  // falls back to an English one reading Spanish.
  const shifting = await open({
    stub: speechStub(VOICES) + `
      setTimeout(() => {
        const only = [{ name: "Mónica", lang: "es-ES" }]
        Object.defineProperty(window.speechSynthesis, "getVoices", { value: () => only })
      }, 600)
    `,
  })
  await shifting.waitForSelector(".prompt")
  await wait(900)
  await shifting.tap(".card")
  await shifting.tap(".speak")
  await spokenAtLeast(shifting, 1)
  check("a voice that vanished falls back to another Spanish one",
    (await shifting.spoken()).at(-1).voice, "Mónica")
  check("and no page errors along the way", shifting.errors, [])
  await shifting.close()
}
