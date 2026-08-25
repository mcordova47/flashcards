import { deckFingerprint, formatVersion, wait } from "./harness.mjs"

export const name = "Progress sheet and next-due"

const FP = deckFingerprint()
const DAY = 86400000
const V = formatVersion()

// A plausible few weeks in: the opening hundred graduated and produced, a
// frontier around 180, three words that keep slipping.
const worked = () => {
  const cards = []
  const add = (rank, box, seen, missed, lapses, dueIn, direction = "recognition") =>
    cards.push({ rank, box, seen, missed, lapses, direction, due: Date.now() + dueIn * DAY })
  for (let r = 1; r <= 100; r++) add(r, 4, 6, 0, 0, 40, "production")
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
    cards.push({ rank: r, box: 4, seen: 6, missed: 0, lapses: 0, direction: "production",
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
  check("mastered means produced, not merely recognised", tiles[1], "100mastered")
  check("and it says what is coming tomorrow", tiles[2], "21due tomorrow")
  check("with the raw numbers behind the percentage", await page.text(".tiles-note"),
    "808 answers · 36 wrong · 100 in production · 2 due now")

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
      cards.push({ rank: r, box: 4, seen: 6, missed: 0, lapses: 0, direction: "production", due: Date.now() + 30 * DAY })
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
      cards.push({ rank: r, box: 2, seen: 4, missed: 0, lapses: 0, direction: "recognition", due: Date.now() - (31 - r) * 1000 })
    for (let r = 31; r <= 1000; r++)
      cards.push({ rank: r, box: 4, seen: 6, missed: 0, lapses: 0, direction: "production", due: Date.now() + 30 * DAY })
    const p = await open({ seed: { version: V, deck: FP, cards } })
    await p.waitForSelector(".prompt")
    for (let i = 0; i < 20; i++) { await p.tap(".card"); await p.tap(".got-it") }
    await p.waitForSelector(".done-title")
    check("no promise of a future review while cards are waiting", await p.$(".next-due"), null)
    await p.close()
  }
}
