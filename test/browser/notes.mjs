import { slugAt, wait } from "./harness.mjs"

export const name = "Notes written from inside the app"

const NOTES = "flashcards.notes.v1"

const openSheet = async page => {
  await page.tap(".panel-toggle")
  ;(await page.byText(".panel-item", "Write a note")).click()
  await page.waitForSelector(".note-draft")
}

// Every key either page maps, among ordinary writing: the space the flip key
// would swallow, the grades, undo, speak, and Enter twice.
const TYPED = "z the hint 1 is 2 confusing s\n\nsecond line"

const saved = page => page.evaluate(k => JSON.parse(localStorage.getItem(k) ?? "null"), NOTES)

export default async ({ base, browser, check, open }) => {
  // --- from the cards, mid-question ---
  const cards = await open()
  await cards.waitForSelector(".prompt")
  // One answered, so there is an answer for `z` to take back if it got through.
  await cards.tap(".card")
  await cards.tap(".got-it")
  const prompt = await cards.text(".prompt")
  check("a second card is up", prompt, slugAt(2))

  await openSheet(cards)
  check("the panel steps aside for the sheet", await cards.$(".panel"), null)
  check("the sheet says what was on screen before anything is typed",
    await cards.text(".note-context"), `/es · ${slugAt(2)} · recognition · “${slugAt(2)}”`)
  check("and the box is ready to type into",
    await cards.evaluate(() => document.activeElement?.className), "note-draft")

  await cards.keyboard.type(TYPED)
  check("every key typed is in the box, spaces and new lines included",
    await cards.$eval(".note-draft", e => e.value), TYPED)
  await cards.tap(".note-save")

  const one = await saved(cards)
  check("the note is saved", one?.notes?.map(n => n.text), [ TYPED.trim() ])
  check("with what was on screen, untyped",
    one.notes[0].context, `/es · ${slugAt(2)} · recognition · “${slugAt(2)}”`)
  check("and when", Math.abs(one.notes[0].at - Date.now()) < 60000, true)
  check("the box is emptied for the next one", await cards.$eval(".note-draft", e => e.value), "")
  check("and the note is listed", await cards.text(".note-text"), TYPED.trim())

  // Enter with the button focused, which is where a tap leaves focus.
  await cards.keyboard.press("Enter")
  await cards.keyboard.press(" ")
  await cards.keyboard.press("z")
  await cards.tap(".sheet-close")
  check("the card behind is the one that was there", await cards.text(".prompt"), prompt)
  check("still unturned", await cards.$(".answer"), null)
  check("and the answer before it was not taken back",
    await cards.$$eval(".pip.done", ps => ps.length), 1)
  check("the notes live under their own key, not the progress",
    (await cards.stored()).cards.length, 1)

  await cards.keyboard.press(" ")
  await wait(90)
  check("with the sheet gone, the keys are the page's again", !!(await cards.$(".answer")), true)

  // A blank note is not a note.
  await openSheet(cards)
  check("the answer showing is recorded too",
    await cards.text(".note-context"), `/es · ${slugAt(2)} · recognition · “${slugAt(2)}” · answer showing`)
  await cards.type(".note-draft", "   \n ")
  await cards.tap(".note-save")
  check("a blank one is not saved", (await saved(cards)).notes.length, 1)
  check("no page errors", cards.errors, [])
  await cards.close()

  // --- from the drills, with an answer half typed ---
  // Opened without `open`, which clears storage: the list is one for the app,
  // and the note from the cards must still be here.
  const verbs = await browser.newPage()
  await verbs.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })
  verbs.errors = []
  verbs.on("pageerror", e => verbs.errors.push(String(e)))
  // Headless Chrome refuses the real clipboard for want of a focused
  // document, so what is checked is what the page hands it. The refusal is
  // checked separately below.
  await verbs.evaluateOnNewDocument(`
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
      writeText: text => { window.__copied = text; return Promise.resolve() },
    }})
  `)
  await verbs.goto(base + "/verbs", { waitUntil: "networkidle0" })
  await verbs.waitForSelector(".verb-answer")
  const sentence = await verbs.$eval(".verb-sentence", e => e.textContent)
  const before = await verbs.$eval(".verb-before", e => e.textContent)
  const after = await verbs.$eval(".verb-after", e => e.textContent)
  const target = await verbs.$eval(".verb-target", e => e.textContent)
  await verbs.type(".verb-answer", "hab")

  await verbs.click(".panel-toggle")
  await wait(90)
  for (const item of await verbs.$$(".panel-item")) {
    if (await item.evaluate(e => e.textContent) === "Write a note") await item.click()
  }
  // The list is read from storage once the sheet is up, so it lands a beat
  // after the sheet does.
  await verbs.waitForSelector(".note-text")
  check("the list is the whole app's, so the cards' note is here",
    await verbs.$$eval(".note-text", ns => ns.map(n => n.textContent)), [ TYPED.trim() ])
  const context = await verbs.$eval(".note-context", e => e.textContent)
  check("the drill's context names the page and the item",
    context.startsWith("/verbs · ") && context.includes(sentence) && context.includes(target), true)
  check("and the gap, but not what goes in it",
    context.endsWith(` · ${before}[…]${after}`), true)

  await verbs.keyboard.type("the frame reads oddly\n")
  await verbs.click(".note-save")
  await wait(90)
  await verbs.keyboard.press("Enter")
  await verbs.click(".sheet-close")
  await wait(90)
  check("what was typed into the answer is still there",
    await verbs.$eval(".verb-answer", e => e.value), "hab")
  check("and it was not checked", await verbs.$(".verb-wrong"), null)
  check("so the question is the one that was asked",
    await verbs.$eval(".verb-sentence", e => e.textContent), sentence)

  // Once checked, the answer is no longer a secret, and what was typed is
  // half of any complaint about the verdict.
  await verbs.keyboard.press("Enter")
  await verbs.waitForSelector(".verb-wrong")
  await verbs.click(".panel-toggle")
  await wait(90)
  for (const item of await verbs.$$(".panel-item")) {
    if (await item.evaluate(e => e.textContent) === "Write a note") await item.click()
  }
  await verbs.waitForSelector(".note-draft")
  const checked = await verbs.$eval(".note-context", e => e.textContent)
  check("after checking, the answer and what was written are both there",
    /\[[^…\]]+\]/.test(checked) && checked.endsWith(" · wrote “hab”"), true)

  // --- surviving a reload, and getting them out ---
  await verbs.reload({ waitUntil: "networkidle0" })
  await verbs.waitForSelector(".panel-toggle")
  await verbs.click(".panel-toggle")
  await wait(90)
  for (const item of await verbs.$$(".panel-item")) {
    if (await item.evaluate(e => e.textContent) === "Write a note") await item.click()
  }
  await verbs.waitForSelector(".note-text")
  check("both survive a reload, newest first",
    await verbs.$$eval(".note-text", ns => ns.map(n => n.textContent)),
    [ "the frame reads oddly", TYPED.trim() ])
  check("counted", await verbs.$eval(".notes-head .sheet-heading", e => e.textContent), "Notes · 2")

  await verbs.click(".note-copy")
  await wait(150)
  const copied = await verbs.evaluate(() => window.__copied)
  const stored = (await saved(verbs)).notes
  const stamp = ms => new Date(ms).toISOString().slice(0, 16).replace("T", " ") + " UTC"
  check("one tap copies them all, oldest first, each with its context",
    copied,
    `${stamp(stored[0].at)} · ${stored[0].context}\n${TYPED.trim()}\n\n` +
      `${stamp(stored[1].at)} · ${stored[1].context}\nthe frame reads oddly`)
  check("and says so", await verbs.$eval(".note-copied", e => e.textContent), "Copied — paste them wherever they are going.")
  check("no page errors", verbs.errors, [])
  await verbs.close()

  // --- a clipboard that is not there ---
  const refused = await open({
    path: "/verbs",
    stub: `Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })`,
  })
  await refused.waitForSelector(".panel-toggle")
  await refused.evaluate((k, v) => localStorage.setItem(k, v), NOTES,
    JSON.stringify({ version: 1, notes: [ { at: 0, context: "/verbs", text: "kept" } ] }))
  await refused.click(".panel-toggle")
  await wait(90)
  for (const item of await refused.$$(".panel-item")) {
    if (await item.evaluate(e => e.textContent) === "Write a note") await item.click()
  }
  await refused.waitForSelector(".note-copy")
  await refused.tap(".note-copy")
  check("a refused copy says so, and where to look instead",
    await refused.text(".note-copied"), "Couldn't copy — select them below instead.")
  check("no page errors", refused.errors, [])
  await refused.close()
}
