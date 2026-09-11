import { deckFingerprint, formatVersion, nonCanonicalRanks, slugAt, wait } from "./harness.mjs"

export const name = "Milestones"

const V = formatVersion()
const FP = deckFingerprint()
const DAY = 86400000
const BARRED = nonCanonicalRanks()

// Mastered means production box 3, except for the words barred from
// production, whose ceiling is recognition box 5.
const mastered = rank => ({
  slug: slugAt(rank), box: BARRED.has(rank) ? 5 : 3, seen: 8, missed: 1, lapses: 0,
  direction: BARRED.has(rank) ? "recognition" : "production", due: Date.now() + 30 * DAY,
})

const seed = cards => ({ version: V, deck: FP, cards })

const finish = async (page, n = 20) => {
  for (let i = 0; i < n; i++) { await page.tap(".card"); await page.tap(".got-it") }
  await page.waitForSelector(".done-title")
  await wait(400)
}

export default async ({ check, open }) => {
  // --- an ordinary session says nothing ---
  {
    const page = await open()
    await page.waitForSelector(".prompt")
    await finish(page)
    check("a session that came to nothing says nothing", await page.$(".milestone"), null)
    await page.close()
  }

  // --- the quietest tier ---
  // Everything here has to be something the finished screen does not already
  // say. A clean sweep was on this list once and came off it: the tally reads
  // "20 cards · 20 got it · 0 again", so a line under it saying "20 out of 20"
  // was the same sentence twice.
  {
    // Three words slipping, all of them one right answer from recovery, and
    // all due now.
    const cards = [181, 182, 183].map(rank => ({
      slug: slugAt(rank), box: 1, seen: 9, missed: 5, lapses: 4,
      direction: "recognition", due: Date.now() - 1000,
    }))
    const page = await open({ seed: seed(cards) })
    await page.waitForSelector(".prompt")
    await finish(page)
    check("the last slipping word coming good earns a sentence",
      await page.text(".milestone"), "Nothing is slipping any more.")
    check("and no more than that", await page.$eval(".milestone", e => e.className),
      "milestone remark")
    check("with the bar left alone", await page.$eval(".deck-progress", e => e.className),
      "deck-progress")
    check("and nothing drawn over the page", await page.$(".confetti"), null)
    await page.close()
  }

  // --- crossing a hundred ---
  {
    const cards = []
    for (let r = 1; r <= 99; r++) cards.push(mastered(r))
    // One card a single correct answer short of mastered, and due now.
    cards.push({ slug: slugAt(100), box: 2, seen: 6, missed: 1, lapses: 0,
                 direction: "production", due: Date.now() - 1000 })
    const page = await open({ seed: seed(cards) })
    await page.waitForSelector(".prompt")
    await finish(page)
    check("a hundred is worth saying", await page.text(".milestone"),
      "That makes 100 words mastered.")
    check("louder than a sentence", await page.$eval(".milestone", e => e.className),
      "milestone flourish")
    // A hundred is a hundred *of* the bar, so the bar is what to look at.
    check("and the bar is marked", await page.$eval(".deck-progress", e => e.className),
      "deck-progress marked")
    check("but still no confetti", await page.$(".confetti"), null)

    // The standing is read again when the next session opens, so the
    // crossing cannot be crossed twice.
    await page.tap(".grade")
    await wait(250)
    await finish(page)
    check("and it is not said twice", (await page.text(".milestone")) !== "That makes 100 words mastered.", true)
    await page.close()
  }

  // --- meeting every word ---
  {
    const cards = []
    for (let r = 1; r <= 980; r++)
      cards.push({ slug: slugAt(r), box: 3, seen: 5, missed: 1, lapses: 0,
                   direction: "recognition", due: Date.now() + 30 * DAY })
    const page = await open({ seed: seed(cards) })
    await page.waitForSelector(".prompt")
    await finish(page)
    check("meeting the whole deck is the loud one", await page.text(".milestone"),
      "You have now met all 1000 words.")
    check("said as such", await page.$eval(".milestone", e => e.className), "milestone burst")
    check("with confetti over the page", (await page.$(".confetti")) !== null, true)
    check("which does not take the taps", await page.$eval(".confetti", e =>
      getComputedStyle(e).pointerEvents), "none")
    await wait(3200)
    check("and clears itself up", await page.$(".confetti"), null)
    check("no page errors", page.errors, [])
    await page.close()
  }

  // --- someone who would rather it did not move ---
  {
    const cards = []
    for (let r = 1; r <= 980; r++)
      cards.push({ slug: slugAt(r), box: 3, seen: 5, missed: 1, lapses: 0,
                   direction: "recognition", due: Date.now() + 30 * DAY })
    const page = await open({ seed: seed(cards) })
    await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }])
    await page.waitForSelector(".prompt")
    await finish(page)
    // The sentence carries the whole message, so skipping the animation
    // costs nothing at all.
    check("the milestone still says what happened", await page.text(".milestone"),
      "You have now met all 1000 words.")
    check("and nothing is thrown across the screen", await page.$(".confetti"), null)
    await page.close()
  }
}
