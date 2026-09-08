import { deckFingerprint, formatVersion, slugAt, spanishDeck, storedAt, wait } from "./harness.mjs"

export const name = "Saved progress and legacy formats"

const FP = deckFingerprint()
// Fixed rather than relative to now, so an exact record can be asserted.
const BASE = 1700000000000

export default async ({ check, open }) => {
  // --- what a session writes ---
  const page = await open()
  await page.waitForSelector(".prompt")
  for (let i = 0; i < 5; i++) { await page.tap(".card"); await page.tap(".got-it") }
  await page.tap(".panel-toggle")
  check("the panel reports what has been seen", await page.text(".panel-note"), "5 of 1000 words seen")
  await page.dismiss()

  const saved = await page.stored()
  check("written at the current format version", saved.version, formatVersion())
  check("carrying the deck fingerprint", saved.deck, FP)
  check("and naming the language it belongs to", saved.language, "es")
  check("holding every studied card", saved.cards.length, 5)
  check("each named by its word rather than its place in the deck",
    saved.cards.map(c => c.slug).sort(), spanishDeck().slice(0, 5).map(c => c.word).sort())
  check("and no rank anywhere in it", saved.cards.every(c => !("rank" in c)), true)

  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: "networkidle0" })
  await page.waitForSelector(".prompt")
  check("a wiped device starts over", await page.text(".prompt"), "yo")
  await page.close()

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
