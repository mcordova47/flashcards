import { deckFingerprint, formatVersion } from "./harness.mjs"

export const name = "Recognition, graduation and production"

const FP = deckFingerprint()
const seed = card => ({ version: formatVersion(), deck: FP, cards: [card] })
const overdue = () => Date.now() - 86400000

export default async ({ check, open }) => {
  // Rank 12 is "that" -> que, the worst collision in the deck.
  const edge = await open({ seed: seed(
    { rank: 12, box: 3, seen: 4, missed: 1, lapses: 0, direction: "recognition", due: overdue() }) })
  await edge.waitForSelector(".prompt")
  check("recognition asks for the English", await edge.text(".direction"), "answer in English")
  check("prompting with the Spanish", await edge.text(".prompt"), "que")
  await edge.tap(".card")
  check("revealing the single gloss", await edge.text(".answer"), "that")
  await edge.tap(".got-it")
  const graduated = (await edge.stored()).cards.find(c => c.rank === 12)
  check("a correct answer at the edge graduates it", graduated.direction, "production")
  check("restarting the box, since producing is unproven", graduated.box, 1)
  await edge.close()

  // Rank 17 is "ese", the second card glossed "that". In production its prompt
  // would be identical to rank 12's, so it must stay in recognition.
  const sibling = await open({ seed: seed(
    { rank: 17, box: 3, seen: 4, missed: 1, lapses: 0, direction: "recognition", due: overdue() }) })
  await sibling.waitForSelector(".prompt")
  check("a sibling of a colliding gloss is asked in recognition", await sibling.text(".prompt"), "ese")
  await sibling.tap(".card")
  await sibling.tap(".got-it")
  const barred = (await sibling.stored()).cards.find(c => c.rank === 17)
  check("it does not graduate", barred.direction, "recognition")
  check("climbing past the graduation box instead", barred.box, 4)
  await sibling.close()

  const many = await open({ seed: seed(
    { rank: 12, box: 1, seen: 5, missed: 1, lapses: 0, direction: "production", due: overdue() }) })
  await many.waitForSelector(".prompt")
  check("production asks for the Spanish", await many.text(".direction"), "answer in Spanish")
  check("prompting with the English", await many.text(".prompt"), "that")
  check("with nothing revealed yet", await many.$(".answer, .answer.many"), null)
  await many.tap(".card")
  check("the reveal shows every valid answer, commonest first",
    await many.text(".answer.many"), "que · ese · aquel · cuanto · ése · aquello")
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
