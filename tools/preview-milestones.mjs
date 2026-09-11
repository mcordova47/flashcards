// Every milestone, without waiting a year for one.
//
//   node tools/preview-milestones.mjs           screenshots, both themes
//   node tools/preview-milestones.mjs --watch   a real window, to see it move
//
// A milestone is a crossing, so each of these seeds a deck one answer short of
// one and then plays the session out. Confetti does not screenshot well; that
// is what --watch is for.

import fs from "fs"
import path from "path"
import {
  REPO, deckFingerprint, formatVersion, nonCanonicalRanks, run, slugAt, wait,
} from "../test/browser/harness.mjs"

const DAY = 86400000
const BARRED = nonCanonicalRanks()
const watching = process.argv.includes("--watch")
const out = path.join(REPO, "preview")

// Mastered is production box 3, except for the words barred from production,
// whose ceiling is recognition box 5.
const mastered = rank => ({
  slug: slugAt(rank), box: BARRED.has(rank) ? 5 : 3, seen: 8, missed: 1, lapses: 0,
  direction: BARRED.has(rank) ? "recognition" : "production", due: Date.now() + 30 * DAY,
})

const met = rank => ({
  slug: slugAt(rank), box: 3, seen: 5, missed: 1, lapses: 0,
  direction: "recognition", due: Date.now() + 30 * DAY,
})

// One answer short of mastered, and due now.
const brink = rank => ({
  slug: slugAt(rank), box: 2, seen: 6, missed: 1, lapses: 0,
  direction: "production", due: Date.now() - 1000,
})

const upTo = (n, make) => Array.from({ length: n }, (_, i) => make(i + 1))

// Slipping, and one right answer from recovery. See Stats.leeches.
const slipping = rank => ({
  slug: slugAt(rank), box: 1, seen: 9, missed: 5, lapses: 4,
  direction: "recognition", due: Date.now() - 1000,
})

const scenes = [
  {
    name: "remark", says: "the last slipping word coming good",
    cards: [181, 182, 183].map(slipping), answers: 20,
  },
  {
    name: "flourish", says: "the hundredth word mastered",
    cards: [...upTo(99, mastered), brink(100)], answers: 20,
  },
  {
    name: "burst-seen", says: "every word met",
    cards: upTo(980, met), answers: 20,
  },
  {
    name: "burst-everything", says: "every word mastered",
    cards: [...upTo(999, mastered), brink(1000)], answers: 1,
  },
]

if (!watching) fs.mkdirSync(out, { recursive: true })

await run("Milestones", async ({ open }) => {
  for (const scene of scenes) {
    for (const scheme of watching ? ["light"] : ["light", "dark"]) {
      const page = await open({
        scheme,
        seed: { version: formatVersion(), deck: deckFingerprint(), cards: scene.cards },
      })
      await page.waitForSelector(".prompt")
      for (let i = 0; i < scene.answers; i++) {
        await page.tap(".card")
        await page.tap(".got-it")
      }
      await page.waitForSelector(".done-title")
      await wait(watching ? 500 : 900)
      const said = await page.text(".milestone")
      if (scheme === "light") console.log(`  ${scene.says.padEnd(36)}${said ?? "(nothing)"}`)
      if (watching) await wait(4000)
      else await page.screenshot({ path: path.join(out, `${scene.name}-${scheme}.png`) })
      await page.close()
    }
  }
  if (!watching) console.log(`\n  written to ${path.relative(REPO, out)}/`)
}, watching ? { headless: false, slowMo: 12 } : {})
