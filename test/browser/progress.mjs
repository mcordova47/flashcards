import { deckFingerprint, formatVersion, nonCanonicalRanks, slugAt, wait } from "./harness.mjs"

export const name = "Progress sheet and next-due"

const FP = deckFingerprint()
const DAY = 86400000
const V = formatVersion()
const BARRED = nonCanonicalRanks()
// Three of the opening hundred share a gloss with an earlier word, so they can
// never be produced; they sit at the top of recognition instead, which is
// their ceiling and counts as mastered all the same.
const PRODUCING = 100 - [...BARRED].filter(r => r <= 100).length

// A plausible few weeks in: the opening hundred graduated and produced, a
// frontier around 180, three words that keep slipping.
const worked = () => {
  const cards = []
  const add = (rank, box, seen, missed, lapses, dueIn, direction = "recognition") =>
    cards.push({ slug: slugAt(rank), box, seen, missed, lapses, direction,
                 due: Date.now() + dueIn * DAY })
  for (let r = 1; r <= 100; r++)
    BARRED.has(r) ? add(r, 5, 6, 0, 0, 40) : add(r, 4, 6, 0, 0, 40, "production")
  for (let r = 101; r <= 160; r++) add(r, 3, 2, 0, 0, 6)
  for (let r = 161; r <= 180; r++) add(r, 1, 3, 1, 0, 0.5)
  add(181, 0, 9, 5, 4, -0.1)
  add(182, 0, 12, 8, 6, -0.1)
  add(183, 1, 7, 3, 3, 0.2)
  return { version: V, deck: FP, cards }
}

// Everything seen, nothing due, one card closest.
const caughtUp = soonestHours => {
  const cards = []
  for (let r = 1; r <= 1000; r++)
    cards.push({ slug: slugAt(r), box: BARRED.has(r) ? 5 : 4, seen: 6, missed: 0, lapses: 0,
                 direction: BARRED.has(r) ? "recognition" : "production",
                 due: Date.now() + (r === 500 ? soonestHours * 3600000 : 20 * DAY) })
  return { version: V, deck: FP, cards }
}

const openSheet = async page => {
  await page.tap(".panel-toggle")
  ;(await page.byText(".panel-item", "See your progress")).click()
  await wait(250)
}

export default async ({ check, open }) => {
  const page = await open({ seed: worked() })
  await page.waitForSelector(".prompt")
  await openSheet(page)

  const tiles = await page.$$eval(".tile", es => es.map(e => e.textContent))
  check("accuracy divides by every wrong answer", tiles[0], "96%correct")
  check("mastered counts produced words and those that can go no further", tiles[1], "100mastered")
  check("and it says what is coming tomorrow", tiles[2], "21due tomorrow")
  check("with the raw numbers behind the percentage", await page.text(".tiles-note"),
    `808 answers · 36 wrong · ${PRODUCING} in production · 2 due now`)

  check("one bar per hundred words", (await page.$$(".band")).length, 10)
  check("the graduated band reads as mastered",
    await page.$$eval(".band:nth-child(1) .seg", es => es.map(e => e.className)), ["seg mastered"])
  check("the frontier band is mixed",
    await page.$$eval(".band:nth-child(2) .seg", es => es.map(e => e.className)),
    ["seg familiar", "seg learning", "seg unseen"])
  check("untouched bands are wholly unseen",
    await page.$$eval(".band:nth-child(10) .seg", es => es.map(e => e.className)), ["seg unseen"])

  const leeches = await page.$$eval(".leech", es => es.map(e => e.textContent))
  check("words that keep slipping are listed", leeches.length, 3)
  check("worst first", leeches[0].endsWith("6"), true)
  check("with a way to act on them", await page.text(".drill"), "Drill these 3")

  // The three leeches are ranks 181-183 with 4, 6 and 3 lapses, so a drill
  // asks the worst of them first and ignores that none of them is due.
  await (await page.byText(".drill", "Drill these 3")).click()
  await wait(250)
  check("drilling closes the sheet", await page.$(".sheet"), null)
  check("and starts on the worst of them", await page.text(".prompt"), slugAt(182))
  check("with a session exactly that long", (await page.$$(".pip")).length, 3)
  // A drill is chosen rather than scheduled, so nothing it produces is
  // evidence: getting a word right straight after reading it off a list of
  // your worst words says nothing about next week.
  const before = await page.stored()
  await page.tap(".card")
  await page.tap(".got-it")
  check("moving on like any other session", await page.text(".prompt"), slugAt(181))
  check("but writing nothing at all", await page.stored(), before)
  check("so there is nothing to undo", await page.$(".hint-action"), null)

  // Again still loops within the drill: that is most of what one is for.
  await page.tap(".card")
  await page.tap(".again")
  check("a missed card still comes round again",
    (await page.$$(".pip")).length, 4)
  check("and still writes nothing", await page.stored(), before)

  await page.tap(".card")
  await page.tap(".got-it")
  await page.tap(".card")
  await page.tap(".got-it")
  await page.waitForSelector(".done-title")
  check("the tally is the session's own", await page.text(".done-stats"),
    "4 cards · 3 got it · 1 again")
  check("with the history still untouched", await page.stored(), before)
  check("and the words still listed as slipping", (await page.stored()).cards.length,
    before.cards.length)

  await page.tap(".grade")
  await wait(250)
  await openSheet(page)

  check("the body is the scrolling region",
    await page.$eval(".sheet-body", e => getComputedStyle(e).overflowY), "auto")
  await page.setViewport({ width: 390, height: 480, deviceScaleFactor: 2 })
  await wait(150)
  check("scrolling on a short screen rather than clipping",
    await page.$eval(".sheet-body", e => e.scrollHeight > e.clientHeight), true)
  check("with the head staying put",
    await page.$eval(".sheet-head", e => e.getBoundingClientRect().top < 60), true)
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })

  await page.tap(".sheet-close")
  check("closing returns to the card", await page.$(".sheet"), null)
  check("with the session undisturbed", await page.text(".prompt"), "cualquier")
  check("no page errors", page.errors, [])
  await page.close()

  // --- how long until the next card ---
  for (const [hours, expected] of [[4, "4 hours"], [0.4, "24 minutes"], [30, "1 day"]]) {
    const p = await open({ seed: caughtUp(hours) })
    await p.waitForSelector(".done-title")
    check(`caught up, waiting ${expected}`, await p.text(".done-stats"), `Nothing due for another ${expected}.`)
    check("and no second line, the headline carries it", await p.$(".next-due"), null)
    await p.close()
  }

  // Finishing a session with nothing else waiting.
  {
    const cards = []
    for (let r = 21; r <= 1000; r++)
      cards.push({ slug: slugAt(r), box: BARRED.has(r) ? 5 : 4, seen: 6, missed: 0, lapses: 0,
                   direction: BARRED.has(r) ? "recognition" : "production", due: Date.now() + 30 * DAY })
    const p = await open({ seed: { version: V, deck: FP, cards } })
    await p.waitForSelector(".prompt")
    for (let i = 0; i < 20; i++) { await p.tap(".card"); await p.tap(".got-it") }
    await p.waitForSelector(".done-title")
    check("a finished session reports its tally", await p.text(".done-stats"), "20 cards · 20 got it · 0 again")
    check("and adds when the next review lands", await p.text(".next-due"), "Next review in 7 days")
    await p.close()
  }

  // ...but stays quiet while cards are still waiting.
  {
    const cards = []
    for (let r = 1; r <= 30; r++)
      cards.push({ slug: slugAt(r), box: 2, seen: 4, missed: 0, lapses: 0, direction: "recognition", due: Date.now() - (31 - r) * 1000 })
    for (let r = 31; r <= 1000; r++)
      cards.push({ slug: slugAt(r), box: BARRED.has(r) ? 5 : 4, seen: 6, missed: 0, lapses: 0,
                   direction: BARRED.has(r) ? "recognition" : "production", due: Date.now() + 30 * DAY })
    const p = await open({ seed: { version: V, deck: FP, cards } })
    await p.waitForSelector(".prompt")
    for (let i = 0; i < 20; i++) { await p.tap(".card"); await p.tap(".got-it") }
    await p.waitForSelector(".done-title")
    check("no promise of a future review while cards are waiting", await p.$(".next-due"), null)
    await p.close()
  }

  // --- "keeps slipping" is present tense ---
  // Its own seed rather than a card added to the one above: every figure on
  // that sheet is an aggregate, so one more card moves the accuracy, the
  // mastered count and the bands along with it.
  {
    const cards = [
      // Forgotten more often than anything else here, and long since
      // recovered. Ranked on the lifetime count alone it would lead the list.
      { slug: slugAt(1), box: 5, seen: 30, missed: 9, lapses: 8,
        direction: "recognition", due: Date.now() + 55 * DAY },
      // Graduated, so it is being asked the harder way round and starts near
      // the bottom of a new ladder. That is arrival, not trouble.
      { slug: slugAt(2), box: 1, seen: 22, missed: 7, lapses: 6,
        direction: "production", due: Date.now() + 2 * DAY },
      // Fell back in production, which is trouble.
      { slug: slugAt(3), box: 0, seen: 18, missed: 8, lapses: 5,
        direction: "production", due: Date.now() - 1000 },
      // Still down where a failure leaves it.
      { slug: slugAt(4), box: 1, seen: 11, missed: 6, lapses: 4,
        direction: "recognition", due: Date.now() - 1000 },
    ]
    const p = await open({ seed: { version: V, deck: FP, cards } })
    await p.waitForSelector(".prompt")
    await openSheet(p)
    const listed = await p.$$eval(".leech-word", es => es.map(e => e.textContent))
    check("a word that climbed back is no longer slipping", listed.includes(slugAt(1)), false)
    check("nor is one that has only just graduated", listed.includes(slugAt(2)), false)
    check("one that fell back in production still is", listed.includes(slugAt(3)), true)
    check("and so is one still down where a failure left it", listed.includes(slugAt(4)), true)
    check("so the list is what is wrong now, not what ever was", listed.length, 2)
    await p.close()
  }
}