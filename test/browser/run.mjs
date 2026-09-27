// Runs the browser suites against the built site.
//
//   npm run verify              every suite
//   npm run verify -- speech    just the ones matching
//
import { run } from "./harness.mjs"
import * as study from "./study.mjs"
import * as offline from "./offline.mjs"
import * as speech from "./speech.mjs"
import * as storage from "./storage.mjs"
import * as production from "./production.mjs"
import * as progress from "./progress.mjs"
import * as language from "./language.mjs"
import * as sync from "./sync.mjs"
import * as milestone from "./milestone.mjs"
import * as verbs from "./verbs.mjs"

// Keyed by file as well as title, so `verify -- speech` finds speech.mjs even
// though its title reads differently.
const suites = [
  ["study", study],
  ["offline", offline],
  ["speech", speech],
  ["storage", storage],
  ["production", production],
  ["progress", progress],
  ["language", language],
  ["sync", sync],
  ["milestone", milestone],
  ["verbs", verbs],
]

const filter = process.argv[2]?.toLowerCase()
const chosen = filter
  ? suites.filter(([key, s]) => key.includes(filter) || s.name.toLowerCase().includes(filter))
  : suites

if (!chosen.length) {
  console.error(`No suite matching "${process.argv[2]}". Available:`)
  for (const [key, s] of suites) console.error(`  ${key.padEnd(12)} ${s.name}`)
  process.exit(1)
}

// A suite that throws gets one more go; one that fails a check does not. The
// only flake seen so far is Puppeteer's "detached Frame" under load, which
// throws, and passes when the suite runs alone. A check that fails is the app
// being wrong, and retrying it would teach people to ignore red. The retry is
// printed, so a suite that keeps needing one is visible rather than hidden.
let failed = 0
for (const [, suite] of chosen) {
  let result = await run(suite.name, suite.default)
  if (result.threw) {
    console.log(`  ↻ retrying "${suite.name}" once, since it threw`)
    result = await run(suite.name, suite.default)
  }
  failed += result.failed
}

console.log(failed
  ? `\n${failed} check(s) failed`
  : `\nAll ${chosen.length} suite${chosen.length === 1 ? "" : "s"} passed`)
process.exit(failed ? 1 : 0)
