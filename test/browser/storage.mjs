import fs from "fs"
import path from "path"
import { deckFingerprint, formatVersion, storageKey, wait } from "./harness.mjs"

export const name = "Backup, merge and legacy formats"

const FP = deckFingerprint()
const card = (rank, over = {}) =>
  ({ rank, box: 1, seen: 1, missed: 0, lapses: 0, due: 1000, ...over })

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
  check("holding every studied card", saved.cards.length, 5)
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
  const merged = (await mine.stored()).cards.sort((a, b) => a.rank - b.rank)
  check("the record with more history behind it wins",
    { box: merged[0].box, seen: merged[0].seen }, { box: 4, seen: 9 })
  check("a card only this device knows survives", merged[1].seen, 3)
  check("a card only the other knows is adopted", merged[2].seen, 2)
  check("and nothing else appeared", merged.length, 3)

  // --- a backup from a different deck would remap onto the wrong words ---
  const foreign = path.join(downloads, "foreign.json")
  fs.writeFileSync(foreign, JSON.stringify({ version: formatVersion(), deck: "ffffffffffff", cards: [card(500)] }))
  const before = await mine.stored()
  await mine.tap(".panel-toggle")
  const [c3] = await Promise.all([
    mine.waitForFileChooser(),
    (await mine.byText(".panel-item", "Load progress from a file")).click(),
  ])
  await c3.accept([foreign])
  await wait(500)
  check("a foreign backup is refused", await mine.text(".notice"), "That backup was made against a different deck.")
  check("leaving progress untouched", await mine.stored(), before)
  await mine.close()

  // --- a payload from before miss counts and directions existed ---
  const old = await open({ seed: { version: 2, deck: FP, cards: [
    { rank: 1, box: 3, due: Date.now() + 6 * 86400000, seen: 1, lapses: 0 },
    { rank: 2, box: 0, due: Date.now() - 1000, seen: 4, lapses: 2 },
  ] } })
  await old.waitForSelector(".prompt")
  check("a legacy payload still resumes on the due card", await old.text(".prompt"), "querer")
  check("and is not rewritten until something changes", (await old.stored()).version, 2)
  await old.tap(".card")
  await old.tap(".got-it")
  const upgraded = await old.stored()
  check("upgrading on the next write", upgraded.version, formatVersion())
  check("keeping the fingerprint", upgraded.deck, FP)
  const untouched = upgraded.cards.find(c => c.rank === 1)
  check("an untouched card keeps its box and history",
    { box: untouched.box, seen: untouched.seen, lapses: untouched.lapses }, { box: 3, seen: 1, lapses: 0 })
  check("gaining a zeroed miss count rather than an invented one", untouched.missed, 0)
  check("and starting in recognition, where every card began", untouched.direction, "recognition")
  check("pre-existing lapses survive", upgraded.cards.find(c => c.rank === 2).lapses, 2)
  check("no page errors", old.errors, [])
  await old.close()
}
