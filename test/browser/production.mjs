import { deckFingerprint, formatVersion } from "./harness.mjs"

export const name = "Recognition, graduation and production"

const FP = deckFingerprint()
const seed = card => ({ version: formatVersion(), deck: FP, cards: [card] })
const overdue = () => Date.now() - 86400000

export default async ({ check, open }) => {
  // Rank 191 is "empezar", which carries the synonym group "to start".
  const edge = await open({ seed: seed(
    { rank: 191, box: 3, seen: 4, missed: 1, lapses: 0, direction: "recognition", due: overdue() }) })
  await edge.waitForSelector(".prompt")
  check("recognition asks for the English", await edge.text(".direction"), "answer in English")
  check("prompting with the Spanish", await edge.text(".prompt"), "empezar")
  await edge.tap(".card")
  check("revealing the single gloss", await edge.text(".answer"), "to start")
  await edge.tap(".got-it")
  const graduated = (await edge.stored()).cards.find(c => c.rank === 191)
  check("a correct answer at the edge graduates it", graduated.direction, "production")
  check("restarting the box, since producing is unproven", graduated.box, 1)
  await edge.close()

  // Rank 254 is "comenzar", a second way to say the same thing. In production
  // its prompt would be identical to rank 191's, so it stays in recognition.
  const sibling = await open({ seed: seed(
    { rank: 254, box: 3, seen: 4, missed: 1, lapses: 0, direction: "recognition", due: overdue() }) })
  await sibling.waitForSelector(".prompt")
  check("a sibling of a synonym group is asked in recognition", await sibling.text(".prompt"), "comenzar")
  await sibling.tap(".card")
  await sibling.tap(".got-it")
  const barred = (await sibling.stored()).cards.find(c => c.rank === 254)
  check("it does not graduate", barred.direction, "recognition")
  check("climbing past the graduation box instead", barred.box, 4)
  await sibling.close()

  const many = await open({ seed: seed(
    { rank: 191, box: 1, seen: 5, missed: 1, lapses: 0, direction: "production", due: overdue() }) })
  await many.waitForSelector(".prompt")
  check("production asks for the Spanish", await many.text(".direction"), "answer in Spanish")
  check("prompting with the English", await many.text(".prompt"), "to start")
  check("with nothing revealed yet", await many.$(".answer, .answer.many"), null)
  await many.tap(".card")
  check("the reveal shows every synonym, commonest first",
    await many.text(".answer.many"), "empezar · comenzar · iniciar")
  await many.close()

  const one = await open({ seed: seed(
    { rank: 8, box: 1, seen: 5, missed: 0, lapses: 0, direction: "production", due: overdue() }) })
  await one.waitForSelector(".prompt")
  check("an unambiguous production prompt", await one.text(".prompt"), "to find")
  await one.tap(".card")
  check("one answer, at full size", await one.text(".answer"), "encontrar")
  check("and not rendered as a list", await one.$(".answer.many"), null)
  await one.tap(".got-it")
  const climbed = (await one.stored()).cards.find(c => c.rank === 8)
  check("production climbs rather than re-graduating", climbed.direction, "production")
  check("advancing a box", climbed.box, 2)
  check("no page errors", one.errors, [])
  await one.close()

  // Progress from before the rule existed: rank 254 already graduated.
  {
    const stale = await open({ seed: { version: formatVersion(), deck: FP, cards: [
      { rank: 191, box: 2, seen: 9, missed: 2, lapses: 1, direction: "production", due: overdue() },
      { rank: 254, box: 3, seen: 7, missed: 3, lapses: 2, direction: "production", due: overdue() + 1000 },
    ] } })
    await stale.waitForSelector(".prompt")
    check("the repair is announced rather than happening silently",
      await stale.text(".notice"), "Fixed 1 repeated prompt")
    const cards = (await stale.stored()).cards
    const moved = cards.find(c => c.rank === 254)
    check("the stranded card is back in recognition", moved.direction, "recognition")
    check("at the box it graduated from", moved.box, 4)
    check("with its history intact", { seen: moved.seen, missed: moved.missed, lapses: moved.lapses },
      { seen: 7, missed: 3, lapses: 2 })
    const kept = cards.find(c => c.rank === 191)
    check("the card that carries the gloss is untouched", kept.direction, "production")
    check("keeping its box", kept.box, 2)
    check("and the fix is written straight away, not on the next answer",
      (await stale.stored()).cards.find(c => c.rank === 254).direction, "recognition")
    await stale.reload({ waitUntil: "networkidle0" })
    await stale.waitForSelector(".prompt")
    check("with nothing left to fix on the next load", await stale.$(".notice"), null)
    await stale.close()
  }

  // Missing in production costs the ladder, not the direction.
  const slipped = await open({ seed: seed(
    { rank: 8, box: 3, seen: 9, missed: 1, lapses: 1, direction: "production", due: overdue() }) })
  await slipped.waitForSelector(".prompt")
  await slipped.tap(".card")
  await slipped.tap(".again")
  const missed = (await slipped.stored()).cards.find(c => c.rank === 8)
  check("a missed production card stays in production", missed.direction, "production")
  check("dropping to box 0", missed.box, 0)
  check("and counting as a lapse", missed.lapses, 2)
  await slipped.close()
}
