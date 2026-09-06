import { formatVersion } from "./harness.mjs"

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

  const first = saved.cards.find(c => c.rank === 1)
  check("a word missed then learned sits low", first.box, 1)
  const easy = saved.cards.find(c => c.rank === 3)
  check("a word known on sight is fast-tracked", easy.box, 3)
  const days = await page.evaluate(due => Math.round((due - Date.now()) / 86400000), easy.due)
  check("and is not due again for a week", days, 7)

  await page.reload({ waitUntil: "networkidle0" })
  await page.waitForSelector(".prompt")
  check("reloading resumes past what was learned", await page.text(".rank"), "#21")
  check("no page errors", page.errors, [])
}
