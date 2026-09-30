import { deckFingerprint, formatVersion, slugAt, wait, wordAt } from "./harness.mjs"

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

// Holds the page's pull of remote progress until the test lets it go, and
// answers it with whatever the test has queued. Sync runs on load, so this is
// the only way to have one land while a sheet is open. No request is made
// while it is held, so the page still reaches network idle.
const holdSync = `
  window.__held = []
  const real = window.fetch
  window.fetch = (url, opts) =>
    String(url).includes("/api/") && !(opts && opts.method && opts.method !== "GET")
      ? new Promise(r => window.__held.push(r))
      : real(url, opts)
  window.__release = body => {
    window.__held.splice(0).forEach(r => r(new Response(body, { status: 200 })))
  }
`

// What another device would hold: the one item, answered and a month out,
// so a rebuild would move past it.
const remote = (language, deck, slug) => JSON.stringify({
  version: formatVersion(), deck, language,
  cards: [ { slug, box: 3, seen: 5, missed: 0, lapses: 0, direction: "recognition",
             due: Date.now() + 30 * 86400000 } ],
})

// The item a page is showing, read the way a note reads it. Opening and
// closing the sheet leaves the session untouched again.
const showing = async page => {
  await page.click(".panel-toggle")
  await wait(90)
  for (const item of await page.$$(".panel-item")) {
    if (await item.evaluate(e => e.textContent) === "Write a note") await item.click()
  }
  await page.waitForSelector(".note-context")
  const slug = (await page.$eval(".note-context", e => e.textContent)).split(" · ")[1]
  return slug
}

export default async ({ base, browser, check, open, noteBlobs }) => {
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
    await cards.text(".note-context"), `/es · ${slugAt(2)} · recognition · “${wordAt(2)}”`)
  check("and the box is ready to type into",
    await cards.evaluate(() => document.activeElement?.className), "note-draft")

  await cards.keyboard.type(TYPED)
  check("every key typed is in the box, spaces and new lines included",
    await cards.$eval(".note-draft", e => e.value), TYPED)
  await cards.tap(".note-save")

  const one = await saved(cards)
  check("the note is saved", one?.notes?.map(n => n.text), [ TYPED.trim() ])
  check("with what was on screen, untyped",
    one.notes[0].context, `/es · ${slugAt(2)} · recognition · “${wordAt(2)}”`)
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
    await cards.text(".note-context"), `/es · ${slugAt(2)} · recognition · “${wordAt(2)}” · answer showing`)
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

  // --- a list this build cannot read is not saved over ---
  // Notes live only on the device, so writing a fresh list over one a newer
  // version wrote would lose it for good.
  const newer = JSON.stringify({ version: 2, notes: [ { at: 0, context: "/verbs", text: "written by a newer app" } ] })
  const stale = await open({ path: "/verbs" })
  await stale.waitForSelector(".panel-toggle")
  await stale.evaluate((k, v) => localStorage.setItem(k, v), NOTES, newer)
  await openSheet(stale)
  await stale.waitForSelector(".note-unreadable")
  check("an unreadable list is said to be so before anything is typed", !!(await stale.$(".note-unreadable")), true)
  await stale.type(".note-draft", "this one must not cost the others")
  await stale.tap(".note-save")
  check("saving writes nothing over it",
    await stale.evaluate(k => localStorage.getItem(k), NOTES), newer)
  check("and what was typed is still in the box",
    await stale.$eval(".note-draft", e => e.value), "this one must not cost the others")
  check("no page errors", stale.errors, [])
  await stale.close()

  // --- a sync landing while a note is written does not rebuild the session ---
  // A control first on each page, so the test can see a rebuild at all.
  const pages = [
    { path: "/", language: "es", deck: deckFingerprint(), label: "the card" },
    { path: "/verbs", language: "verbs", deck: "none", label: "the drill" },
  ]
  for (const { path, language, deck, label } of pages) {
    for (const sheetOpen of [ false, true ]) {
      const page = await open({ path, stub: holdSync })
      await page.waitForSelector(".panel-toggle")
      await page.waitForFunction(() => window.__held.length > 0)
      const before = await showing(page)
      if (!sheetOpen) { await page.click(".sheet-close"); await wait(90) }
      await page.evaluate(body => window.__release(body), remote(language, deck, before))
      await wait(400)
      if (sheetOpen) { await page.click(".sheet-close"); await wait(90) }
      const after = await showing(page)
      check(sheetOpen
        ? `with the sheet open, ${label} stays the one the note is about`
        : `with nothing open, a sync moves ${label} on`,
        sheetOpen ? after : after !== before, sheetOpen ? before : true)
      check("no page errors", page.errors, [])
      await page.close()
    }
  }

  // --- delivered to where the maintainer will see them ---
  // Pages in one browser share storage, so earlier blocks' notes go up under
  // earlier keys as each page loads. Everything here is read under the key of
  // the page at hand.
  const SENT = "flashcards.notes.sent.v1"
  const keyOf = page => page.evaluate(() => localStorage.getItem("flashcards.sync-key"))
  const sentOf = page => page.evaluate(k => localStorage.getItem(k), SENT)
  const under = key => [...noteBlobs].filter(([k]) => k.startsWith(`${key}/`))
  const texts = key => under(key).map(([, v]) => JSON.parse(v).text).sort()
  const write = async (page, text) => {
    await openSheet(page)
    await page.type(".note-draft", text)
    await page.tap(".note-save")
    await page.waitForNetworkIdle({ idleTime: 150 })
    await page.tap(".sheet-close")
  }
  const puts = page => {
    const seen = []
    page.on("request", r => {
      if (r.url().includes("/api/notes/") && r.method() === "PUT") seen.push(JSON.parse(r.postData()).notes.map(n => n.text))
    })
    return seen
  }
  // A page syncs as it loads, which is when a note left behind goes up.
  const reload = async page => {
    await page.reload({ waitUntil: "networkidle0" })
    await page.waitForSelector(".panel-toggle")
    await page.waitForNetworkIdle({ idleTime: 150 })
  }

  const phone = await open()
  await phone.waitForSelector(".prompt")
  const key = await keyOf(phone)
  const sent = puts(phone)

  await openSheet(phone)
  check("the sheet says where a note goes before anything is typed",
    await phone.text(".note-where"),
    "Notes are kept on this device and sent to the person who looks after this app, for them to read.")
  // `.sheet-note` pulls itself up under a heading, which under a button
  // put the line beneath the button's bottom edge.
  const [ button, line ] = await phone.$$eval([ ".note-save", ".note-where" ].join(","),
    es => es.map(e => { const r = e.getBoundingClientRect(); return { top: r.top, bottom: r.bottom } }))
  check("and clear of the button above it", line.top >= button.bottom, true)
  await phone.tap(".sheet-close")

  await write(phone, "sent as soon as it is saved")
  check("a note written online reaches the store straight away", texts(key), [ "sent as soon as it is saved" ])
  const [ [ blobKey, blob ] ] = under(key)
  const local = (await saved(phone)).notes[0]
  check("at its moment, under this device's key", blobKey, `${key}/${local.at}.json`)
  check("as the note itself, context and all", JSON.parse(blob), local)
  check("and the device remembers it went", await sentOf(phone), "1")

  await phone.setOfflineMode(true)
  await write(phone, "written on a train")
  check("one written offline is still saved", (await saved(phone)).notes.length, 2)
  check("but has not gone", texts(key), [ "sent as soon as it is saved" ])
  check("and is not counted as gone", await sentOf(phone), "1")
  await phone.setOfflineMode(false)

  sent.length = 0
  await reload(phone)
  check("it goes up on the next sync", texts(key), [ "sent as soon as it is saved", "written on a train" ])
  check("in one request, carrying only it", sent, [ [ "written on a train" ] ])
  check("and both are counted", await sentOf(phone), "2")

  sent.length = 0
  await reload(phone)
  check("a sync with nothing new sends nothing", sent.length, 0)

  // The case a bare resend-everything gets wrong: read on the server and
  // deleted there, it would come straight back from this phone.
  noteBlobs.delete(blobKey)
  await reload(phone)
  check("a note deleted once read does not come back", texts(key), [ "written on a train" ])

  // Everything again, as a device that lost count would send.
  noteBlobs.set(blobKey, blob)
  await phone.evaluate(k => localStorage.removeItem(k), SENT)
  sent.length = 0
  await reload(phone)
  check("a device that lost count sends everything again", sent, [ [ "sent as soon as it is saved", "written on a train" ] ])
  check("and each is still stored once", under(key).length, 2)
  check("counted again", await sentOf(phone), "2")

  // A count above the list's length was taken against some other list. It
  // must come down, or nothing would be counted as sent until the list
  // outgrew it.
  await phone.evaluate(k => localStorage.setItem(k, "9"), SENT)
  sent.length = 0
  await reload(phone)
  check("a count larger than the list sends everything", sent.length, 1)
  check("and is brought back to the list's length", await sentOf(phone), "2")

  // A server at its cap refuses; the note must wait, not be counted as sent.
  for (let i = 0; i < 98; i++) noteBlobs.set(`${key}/${i}.json`, JSON.stringify({ at: i, context: "/", text: "filler" }))
  await write(phone, "one too many")
  check("a note over the cap is refused", texts(key).includes("one too many"), false)
  check("and not counted", await sentOf(phone), "2")
  noteBlobs.delete(`${key}/0.json`)
  await reload(phone)
  check("once a place is freed, it goes", texts(key).includes("one too many"), true)
  check("and is counted", await sentOf(phone), "3")
  check("no page errors", phone.errors, [])
  await phone.close()

  // --- a note too long to send ---
  // One the server refuses would be in every batch from then on, and hold up
  // every note after it. Set rather than typed: five thousand keystrokes.
  const long = await open()
  await long.waitForSelector(".prompt")
  const longKey = await keyOf(long)
  const big = "ñ".repeat(2600)
  await openSheet(long)
  await long.$eval(".note-draft", (e, v) => { e.value = v }, big)
  await long.tap(".note-save")
  check("is refused, and says why",
    await long.text(".note-too-long"), "That's too long to send in one note. Shorten it, or split it into two.")
  check("is left in the box to cut down", await long.$eval(".note-draft", e => e.value), big)
  check("and is not saved", await saved(long), null)
  await long.$eval(".note-draft", e => { e.value = "" })
  await long.type(".note-draft", "a short one after it")
  await long.tap(".note-save")
  await long.waitForNetworkIdle({ idleTime: 150 })
  check("the next one is saved", (await saved(long)).notes.map(n => n.text), [ "a short one after it" ])
  check("and the warning goes", await long.$(".note-too-long"), null)
  check("and it is delivered", texts(longKey), [ "a short one after it" ])
  await long.tap(".sheet-close")

  // Saved before the sheet refused them, so already on a device.
  await long.evaluate((k, v) => localStorage.setItem(k, v), NOTES, JSON.stringify({ version: 1, notes: [
    { at: 1, context: "/", text: big },
    { at: 2, context: "/", text: "written after the long one" },
  ] }))
  await long.evaluate(k => localStorage.removeItem(k), SENT)
  await reload(long)
  check("an old one too long to send does not hold up the ones after it",
    texts(longKey), [ "a short one after it", "written after the long one" ])
  check("which are counted, so it is not tried again", await sentOf(long), "2")
  await openSheet(long)
  // The list is read once the sheet is up, so it lands a beat after.
  await long.waitForSelector(".note-text")
  check("the sheet says which one was not sent",
    await long.$$eval(".note-unsent", ns => ns.map(n => n.closest(".note").querySelector(".note-text").textContent.length)),
    [ big.length ])
  check("no page errors", long.errors, [])
  await long.close()

  // A list this build cannot read is not one to send.
  const newerPage = await open()
  await newerPage.waitForSelector(".prompt")
  const newerKey = await keyOf(newerPage)
  await newerPage.evaluate((k, v) => localStorage.setItem(k, v), NOTES, newer)
  await reload(newerPage)
  check("an unreadable list is not sent", under(newerKey), [])
  check("no page errors", newerPage.errors, [])
  await newerPage.close()

  // The drills sync too, and deliver as they do.
  const drills = await open({ path: "/verbs" })
  await drills.waitForSelector(".panel-toggle")
  const drillsKey = await keyOf(drills)
  await drills.evaluate((k, v) => localStorage.setItem(k, v), NOTES,
    JSON.stringify({ version: 1, notes: [ { at: 5, context: "/verbs", text: "left from before" } ] }))
  await reload(drills)
  check("the drills deliver what is waiting", texts(drillsKey), [ "left from before" ])
  check("no page errors", drills.errors, [])
  await drills.close()
}
