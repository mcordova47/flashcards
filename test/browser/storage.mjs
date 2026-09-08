import fs from "fs"
import path from "path"
import { deckFingerprint, formatVersion, slugAt, spanishDeck, storedAt, wait } from "./harness.mjs"

export const name = "Backup, merge and legacy formats"

const FP = deckFingerprint()
// Fixed rather than relative to now, so an exact record can be asserted.
const BASE = 1700000000000

// What v5 writes: the card names itself.
const card = (rank, over = {}) =>
  ({ slug: slugAt(rank), box: 1, seen: 1, missed: 0, lapses: 0, due: 1000, ...over })

export default async ({ check, open, downloads, browser }) => {
  const page = await open()
  await page.waitForSelector(".prompt")
  const client = await page.createCDPSession()
  await client.send("Page.setDownloadBehavior", { behavior: "allow", downloadPath: downloads })

  for (let i = 0; i < 5; i++) { await page.tap(".card"); await page.tap(".got-it") }
  await page.tap(".panel-toggle")
  check("the panel reports what has been seen", await page.text(".panel-note"), "5 of 1000 words seen")

  ;(await page.byText(".panel-item", "Save progress to a file")).click()
  await wait(400)
  const file = path.join(downloads, "palabras-progress.json")
  check("a file was written", fs.existsSync(file), true)
  const saved = JSON.parse(fs.readFileSync(file, "utf-8"))
  check("at the current format version", saved.version, formatVersion())
  check("carrying the deck fingerprint", saved.deck, FP)
  check("and naming the language it belongs to", saved.language, "es")
  check("holding every studied card", saved.cards.length, 5)
  check("each named by its word rather than its place in the deck",
    saved.cards.map(c => c.slug).sort(), spanishDeck().slice(0, 5).map(c => c.word).sort())
  check("and no rank anywhere in the file", saved.cards.every(c => !("rank" in c)), true)
  check("and identical to what localStorage holds", saved, await page.stored())
  check("with a notice confirming it", await page.text(".notice"), "Saved palabras-progress.json")

  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: "networkidle0" })
  await page.waitForSelector(".prompt")
  check("a wiped device starts over", await page.text(".prompt"), "yo")

  await page.tap(".panel-toggle")
  const [chooser] = await Promise.all([
    page.waitForFileChooser(),
    (await page.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await chooser.accept([file])
  await wait(500)
  check("restoring is confirmed", await page.text(".notice"), "Loaded backup · 5 words seen")
  check("and resumes past what was learned", await page.text(".prompt"), "poder")
  await page.close()

  // --- merging two histories ---
  const mine = await open({ seed: { version: formatVersion(), deck: FP,
    cards: [card(1, { box: 1, seen: 1 }), card(2, { box: 2, seen: 3 })] } })
  await mine.waitForSelector(".prompt")
  const theirs = path.join(downloads, "other-device.json")
  fs.writeFileSync(theirs, JSON.stringify({ version: formatVersion(), deck: FP,
    cards: [card(1, { box: 4, seen: 9 }), card(3, { box: 1, seen: 2 })] }))
  await mine.tap(".panel-toggle")
  const [c2] = await Promise.all([
    mine.waitForFileChooser(),
    (await mine.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await c2.accept([theirs])
  await wait(500)
  const merged = (await mine.stored()).cards
  check("the record with more history behind it wins",
    { box: storedAt(merged, 1).box, seen: storedAt(merged, 1).seen }, { box: 4, seen: 9 })
  check("a card only this device knows survives", storedAt(merged, 2).seen, 3)
  check("a card only the other knows is adopted", storedAt(merged, 3).seen, 2)
  check("and nothing else appeared", merged.length, 3)

  // --- a backup from a deck that has since moved ---
  // Slugs mean the same word in every version of the deck, so a fingerprint
  // mismatch no longer has anything to say about a v5 file. This is the whole
  // point of the rekey, and the case that used to be refused.
  const foreign = path.join(downloads, "foreign.json")
  fs.writeFileSync(foreign, JSON.stringify({ version: formatVersion(), deck: "ffffffffffff", cards: [card(500)] }))
  await mine.tap(".panel-toggle")
  const [c3] = await Promise.all([
    mine.waitForFileChooser(),
    (await mine.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await c3.accept([foreign])
  await wait(500)
  check("a backup keyed by slug crosses a deck change", await mine.text(".notice"), "Loaded backup · 4 words seen")
  check("bringing its word with it", storedAt((await mine.stored()).cards, 500).seen, 1)

  // But an older file names its cards by position, and a moved deck means no
  // way to tell which word each position stood for.
  const ancient = path.join(downloads, "ancient.json")
  fs.writeFileSync(ancient, JSON.stringify({ version: 4, deck: "ffffffffffff",
    cards: [{ rank: 700, box: 1, seen: 1, missed: 0, lapses: 0, direction: "recognition", due: BASE }] }))
  const before = await mine.stored()
  await mine.tap(".panel-toggle")
  const [c4] = await Promise.all([
    mine.waitForFileChooser(),
    (await mine.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await c4.accept([ancient])
  await wait(500)
  check("but one keyed by position is refused, having nothing to place it by",
    await mine.text(".notice"), "That backup predates a deck change, so its words can't be matched up.")
  check("leaving progress untouched", await mine.stored(), before)

  // Slugs belong to one deck, and the two decks share the word `mal`. Without
  // this the German file would pour a thousand inert entries into the Spanish
  // history, report them all as words seen, and hand `mal` the wrong past.
  const german = path.join(downloads, "german.json")
  fs.writeFileSync(german, JSON.stringify({ version: formatVersion(), language: "de", deck: deckFingerprint("de"),
    cards: [{ slug: "mal", box: 5, seen: 20, missed: 0, lapses: 0, direction: "production", due: BASE }] }))
  await mine.tap(".panel-toggle")
  const [c5] = await Promise.all([
    mine.waitForFileChooser(),
    (await mine.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await c5.accept([german])
  await wait(500)
  check("a backup for the other language is refused", await mine.text(".notice"),
    "That backup is for a different language.")
  check("with the Spanish history untouched", await mine.stored(), before)
  check("no page errors", mine.errors, [])
  await mine.close()

  // --- v4 progress, at the size a real device carries ---
  // Rank-keyed history can only be placed by looking each rank up in the deck,
  // which is sound exactly while the fingerprint still matches. This is the
  // last version of the app that can do it.
  const realistic = Array.from({ length: 200 }, (_, i) => ({
    rank: i + 1, box: (i + 1) % 6, seen: i + 1, missed: (i + 1) % 3, lapses: (i + 1) % 4,
    direction: "recognition", due: BASE + (i + 1) * 1000,
  }))
  const carried = await open({ seed: { version: 4, deck: FP, cards: realistic } })
  await carried.waitForSelector(".prompt")
  const placed = await carried.stored()
  check("every card came across", placed.cards.length, 200)
  check("onto the word that stood at its rank",
    placed.cards.map(c => c.slug).sort(), spanishDeck().slice(0, 200).map(c => c.word).sort())
  check("with its history intact", storedAt(placed.cards, 137),
    { slug: slugAt(137), box: 137 % 6, seen: 137, missed: 137 % 3, lapses: 137 % 4,
      direction: "recognition", due: BASE + 137 * 1000 })
  check("rewritten at the current version on the spot", placed.version, formatVersion())
  await carried.reload({ waitUntil: "networkidle0" })
  await carried.waitForSelector(".prompt")
  check("and not touched again on the next load", await carried.stored(), placed)
  check("no page errors", carried.errors, [])
  await carried.close()

  // The same history against a deck that has moved. Placing it is guesswork,
  // but it is the guess the app has been showing all along, so it is kept and
  // the console says so rather than the history being thrown away.
  const drifted = await open({ seed: { version: 4, deck: "ffffffffffff", cards: [
    { rank: 2, box: 3, seen: 5, missed: 1, lapses: 0, direction: "recognition", due: BASE },
  ] } })
  await drifted.waitForSelector(".prompt")
  check("progress from a moved deck is kept rather than discarded",
    (await drifted.stored()).cards.map(c => c.slug), [ slugAt(2) ])
  await drifted.close()

  // --- a payload from before miss counts, directions or slugs existed ---
  const old = await open({ seed: { version: 2, deck: FP, cards: [
    { rank: 1, box: 3, due: Date.now() + 6 * 86400000, seen: 1, lapses: 0 },
    { rank: 2, box: 0, due: Date.now() - 1000, seen: 4, lapses: 2 },
  ] } })
  await old.waitForSelector(".prompt")
  check("a legacy payload still resumes on the due card", await old.text(".prompt"), "querer")
  const upgraded = await old.stored()
  check("upgrading as it is read", upgraded.version, formatVersion())
  check("keeping the fingerprint", upgraded.deck, FP)
  const untouched = storedAt(upgraded.cards, 1)
  check("an untouched card keeps its box and history",
    { box: untouched.box, seen: untouched.seen, lapses: untouched.lapses }, { box: 3, seen: 1, lapses: 0 })
  check("gaining a zeroed miss count rather than an invented one", untouched.missed, 0)
  check("and starting in recognition, where every card began", untouched.direction, "recognition")
  check("pre-existing lapses survive", storedAt(upgraded.cards, 2).lapses, 2)
  check("no page errors", old.errors, [])
  await old.close()
}
