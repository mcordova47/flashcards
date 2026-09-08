import { formatVersion, slugAt, storedAt, wait } from "./harness.mjs"

export const name = "Study loop"

export default async ({ check, open }) => {
  const page = await open()
  await page.waitForSelector(".prompt")

  check("a fresh learner starts on the most frequent word", await page.text(".prompt"), "yo")
  check("the rank is shown", await page.text(".rank"), "#1")
  check("the answer is hidden before the flip", await page.$(".answer"), null)
  check("a session is twenty cards", (await page.$$(".pip")).length, 20)
  check("the hint invites a tap", await page.text(".hint"), "tap anywhere to flip")

  await page.tap(".card")
  check("flipping reveals the English", await page.text(".answer"), "I")
  check("and Spanish has no examples to show", await page.$(".example"), null)
  check("the prompt stays, shrunk", await page.text(".prompt.small"), "yo")
  check("two grades appear", (await page.$$(".grade")).length, 2)

  await page.tap(".again")
  check("it advances to the next word", await page.text(".prompt"), "querer")
  check("and the queue grew by the requeued card", (await page.$$(".pip")).length, 21)

  const order = ["querer"]
  for (let i = 0; i < 4; i++) {
    await page.tap(".card")
    await page.tap(".got-it")
    order.push(await page.text(".prompt"))
  }
  check("a missed card returns five cards later", order, ["querer", "este", "sí", "no", "yo"])

  await page.keyboard.press(" ")
  check("space flips", await page.text(".answer"), "I")
  await page.keyboard.press("ArrowRight")
  await new Promise(r => setTimeout(r, 90))
  check("an arrow grades", await page.text(".prompt"), "poder")

  for (let i = 0; i < 40 && !(await page.$(".done-title")); i++) {
    await page.tap(".card")
    await page.tap(".got-it")
  }
  check("the session ends with a summary", await page.text(".done-title"), "¡Bien hecho!")
  check("counting the words seen", await page.text(".deck-count"), "20 of 1000 words seen")
  check("and offering another round", await page.text(".grade.got-it"), "Study 20 more")

  const saved = await page.stored()
  check("progress is written at the current format version", saved.version, formatVersion())
  check("every answered card was written", saved.cards.length, 20)

  const first = storedAt(saved.cards, 1)
  check("a word missed then learned sits low", first.box, 1)
  const easy = storedAt(saved.cards, 3)
  check("a word known on sight is fast-tracked", easy.box, 3)
  const days = await page.evaluate(due => Math.round((due - Date.now()) / 86400000), easy.due)
  check("and is not due again for a week", days, 7)

  await page.reload({ waitUntil: "networkidle0" })
  await page.waitForSelector(".prompt")
  check("reloading resumes past what was learned", await page.text(".rank"), "#21")
  check("no page errors", page.errors, [])

  // --- undo ---
  // The only action in the app that used to be unrecoverable: a mis-tapped
  // "Got it" pushes a word you did not know three weeks out, silently.
  const slip = await open()
  await slip.waitForSelector(".prompt")
  check("nothing to undo before anything is answered", await slip.$(".undo"), null)

  await slip.tap(".card")
  await slip.tap(".got-it")
  check("a grade offers one", await slip.text(".undo"), "Undo")
  check("having moved on", await slip.text(".prompt"), slugAt(2))
  await slip.tap(".undo")
  check("undoing goes back to the card", await slip.text(".prompt"), slugAt(1))
  // Still face up, with both grades to hand. You undo in order to press the
  // other button, and putting the card back face down would make you flip it
  // again to get there.
  check("still showing its answer", await slip.text(".answer"), "I")
  check("with both grades to hand", (await slip.$$(".grade")).length, 2)
  check("and the offer is gone, because one step is all there is",
    await slip.$(".undo"), null)
  check("with the history it wrote taken back out of storage",
    (await slip.stored()).cards.length, 0)

  // Each grade replaces the snapshot rather than stacking, so undo always
  // means the most recent answer and never an older one.
  for (let i = 0; i < 3; i++) { await slip.tap(".card"); await slip.tap(".got-it") }
  await slip.tap(".undo")
  check("only ever the last of several", (await slip.stored()).cards.length, 2)
  check("landing on the card that was graded", await slip.text(".prompt"), slugAt(3))

  // Again drops a card to box 0 and requeues it a few places later, so undo
  // has a queue to put back as well as a record.
  await slip.tap(".card")
  await slip.tap(".again")
  const requeued = (await slip.evaluate(() => document.querySelectorAll(".pip").length))
  await slip.tap(".undo")
  check("a requeue is taken back too",
    await slip.evaluate(() => document.querySelectorAll(".pip").length), requeued - 1)
  check("no page errors", slip.errors, [])
  await slip.close()
}